import runpod
import os, websocket, base64, json, uuid, logging
import urllib.request, urllib.parse, binascii
import subprocess, time

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

server_address = os.getenv('SERVER_ADDRESS', '127.0.0.1')
client_id = str(uuid.uuid4())

REMIX_LORA = "NSFW/Wan2.2_Remix_NSFW_i2v_14b_low_lighting_fp8_e4m3fn_v3.0.safetensors"

def to_nearest_multiple_of_16(value):
    adjusted = int(round(float(value) / 16.0) * 16)
    return max(adjusted, 16)

def process_input(input_data, temp_dir, output_filename, input_type):
    if input_type == "path":
        return input_data
    elif input_type == "url":
        os.makedirs(temp_dir, exist_ok=True)
        file_path = os.path.abspath(os.path.join(temp_dir, output_filename))
        result = subprocess.run(['wget', '-O', file_path, '--no-verbose', input_data],
                                capture_output=True, text=True)
        if result.returncode != 0:
            raise Exception(f"下載失敗: {result.stderr}")
        return file_path
    elif input_type == "base64":
        decoded = base64.b64decode(input_data)
        os.makedirs(temp_dir, exist_ok=True)
        file_path = os.path.abspath(os.path.join(temp_dir, output_filename))
        with open(file_path, 'wb') as f:
            f.write(decoded)
        return file_path
    else:
        raise Exception(f"不支援的輸入類型: {input_type}")

def queue_prompt(prompt):
    p = {"prompt": prompt, "client_id": client_id}
    data = json.dumps(p).encode('utf-8')
    req = urllib.request.Request(f"http://{server_address}:8188/prompt", data=data)
    return json.loads(urllib.request.urlopen(req).read())

def get_history(prompt_id):
    with urllib.request.urlopen(f"http://{server_address}:8188/history/{prompt_id}") as r:
        return json.loads(r.read())

def get_videos(ws, prompt):
    prompt_id = queue_prompt(prompt)['prompt_id']
    while True:
        out = ws.recv()
        if isinstance(out, str):
            msg = json.loads(out)
            if msg['type'] == 'executing':
                if msg['data']['node'] is None and msg['data']['prompt_id'] == prompt_id:
                    break
    history = get_history(prompt_id)[prompt_id]
    output_videos = {}
    for node_id, node_output in history['outputs'].items():
        if 'gifs' in node_output:
            videos = []
            for video in node_output['gifs']:
                with open(video['fullpath'], 'rb') as f:
                    videos.append(base64.b64encode(f.read()).decode('utf-8'))
            output_videos[node_id] = videos
    return output_videos

def handler(job):
    job_input = job.get("input", {})
    task_id = f"task_{uuid.uuid4()}"

    # 圖片輸入
    if "image_path" in job_input:
        image_path = process_input(job_input["image_path"], task_id, "input.jpg", "path")
    elif "image_url" in job_input:
        image_path = process_input(job_input["image_url"], task_id, "input.jpg", "url")
    elif "image_base64" in job_input:
        image_path = process_input(job_input["image_base64"], task_id, "input.jpg", "base64")
    else:
        image_path = "/example_image.png"

    # LoRA 設定（預設使用 Remix NSFW LoRA）
    lora_pairs = job_input.get("lora_pairs", [
        {"high": REMIX_LORA, "low": REMIX_LORA, "high_weight": 1.0, "low_weight": 1.0}
    ])[:4]

    with open("/wan22_remix_i2v_api.json", 'r') as f:
        prompt = json.load(f)

    length  = job_input.get("length", 81)
    steps   = job_input.get("steps", 10)
    seed    = job_input.get("seed", 42)

    prompt["244"]["inputs"]["image"]           = image_path
    prompt["541"]["inputs"]["num_frames"]      = length
    prompt["135"]["inputs"]["positive_prompt"] = job_input.get("prompt", "cinematic video, smooth motion")
    prompt["135"]["inputs"]["negative_prompt"] = job_input.get("negative_prompt",
        "bright tones, overexposed, static, blurred details, worst quality, low quality")
    prompt["220"]["inputs"]["seed"]            = seed
    prompt["540"]["inputs"]["seed"]            = seed
    prompt["540"]["inputs"]["cfg"]             = job_input.get("cfg", 2.0)
    prompt["498"]["inputs"]["context_overlap"] = job_input.get("context_overlap", 48)
    prompt["498"]["inputs"]["context_frames"]  = length
    prompt["235"]["inputs"]["value"]           = to_nearest_multiple_of_16(job_input.get("width", 480))
    prompt["236"]["inputs"]["value"]           = to_nearest_multiple_of_16(job_input.get("height", 832))

    if "834" in prompt:
        prompt["834"]["inputs"]["steps"] = steps
    if "829" in prompt:
        prompt["829"]["inputs"]["step"] = int(steps * 0.6)

    for i, pair in enumerate(lora_pairs):
        if pair.get("high"):
            prompt["279"]["inputs"][f"lora_{i+1}"]     = pair["high"]
            prompt["279"]["inputs"][f"strength_{i+1}"] = pair.get("high_weight", 1.0)
        if pair.get("low"):
            prompt["553"]["inputs"][f"lora_{i+1}"]     = pair["low"]
            prompt["553"]["inputs"][f"strength_{i+1}"] = pair.get("low_weight", 1.0)

    # 等待 ComfyUI 就緒
    for i in range(180):
        try:
            urllib.request.urlopen(f"http://{server_address}:8188/", timeout=5)
            break
        except:
            if i == 179:
                raise Exception("ComfyUI 連線逾時")
            time.sleep(1)

    # WebSocket 連線
    ws = websocket.WebSocket()
    for i in range(36):
        try:
            ws.connect(f"ws://{server_address}:8188/ws?clientId={client_id}")
            break
        except:
            if i == 35:
                raise Exception("WebSocket 連線逾時")
            time.sleep(5)

    videos = get_videos(ws, prompt)
    ws.close()

    for node_id in videos:
        if videos[node_id]:
            return {"video": videos[node_id][0]}

    return {"error": "找不到輸出影片"}

runpod.serverless.start({"handler": handler})