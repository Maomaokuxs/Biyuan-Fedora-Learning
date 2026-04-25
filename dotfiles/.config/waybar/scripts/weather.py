#!/usr/bin/env python3
import json
import requests

def get_weather():
    try:
        # 1. 尝试获取 JSON 数据，增加超时，并伪装成浏览器 Header 减少被限流几率
        headers = {'User-Agent': 'Mozilla/5.0'}
        response = requests.get("https://wttr.in/Ganzhou?format=j1", headers=headers, timeout=15)
        
        if response.status_code != 200:
            return {"text": "󰖪 ", "tooltip": f"服务器响应错误: {response.status_code}"}

        data = response.json()

        # 2. 关键防御：检查数据结构中必要的 key 是否存在
        if not data or 'current_condition' not in data:
            return {"text": "󰖪 ", "tooltip": "数据结构异常：wttr.in 可能正在限流"}

        current = data['current_condition'][0]
        temp_c = current.get('temp_C', '??')
        weather_code = current.get('weatherCode', '113')
        
        # 优先取中文，没有则取英文描述
        desc = "未知"
        if 'lang_zh' in current and current['lang_zh']:
            desc = current['lang_zh'][0]['value']
        elif 'weatherDesc' in current and current['weatherDesc']:
            desc = current['weatherDesc'][0]['value']

        # 图标映射
        icons = {
            "113": "󰖙", "116": "󰖕", "119": "󰖐", "122": "󰖐",
            "143": "󰖑", "176": "󰖗", "200": "󰙾", "296": "󰖗",
            "302": "󰖖", "338": "󰼶",
        }
        icon = icons.get(weather_code, "󰖐")

        # 提取地理位置
        area = "未知地点"
        if 'nearest_area' in data and data['nearest_area']:
            area = data['nearest_area'][0]['areaName'][0]['value']

        return {
            "text": f"{icon} {temp_c}°C",
            "tooltip": f"城市: {area}\n状态: {desc}\n体感: {current.get('FeelsLikeC', '??')}°C\n湿度: {current.get('humidity', '??')}%",
            "class": "weather"
        }

    except Exception as e:
        return {"text": "󰖪 ", "tooltip": f"发生异常: {str(e)}"}

if __name__ == "__main__":
    # 打印 JSON 给 Waybar
    print(json.dumps(get_weather()))
