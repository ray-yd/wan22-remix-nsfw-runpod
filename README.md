# Wan2.2 Remix NSFW I2V

Wan2.2 Image-to-Video with FX-FeiHou Remix NSFW LoRA on RunPod Serverless.

## Input Parameters

| 參數                                  | 類型   | 預設值 | 說明       |
| ------------------------------------- | ------ | ------ | ---------- |
| image_url / image_base64 / image_path | string | -      | 輸入圖片   |
| prompt                                | string | -      | 影片描述   |
| negative_prompt                       | string | -      | 負向提示詞 |
| width                                 | int    | 480    | 影片寬度   |
| height                                | int    | 832    | 影片高度   |
| length                                | int    | 81     | 幀數       |
| steps                                 | int    | 10     | 生成步驟數 |
| seed                                  | int    | 42     | 隨機種子   |
| cfg                                   | float  | 2.0    | CFG 強度   |

## Request Example

```json
{
  "input": {
    "image_url": "https://example.com/photo.jpg",
    "prompt": "cinematic video, smooth motion",
    "width": 480,
    "height": 832,
    "length": 81,
    "steps": 10,
    "seed": 42
  }
}
```