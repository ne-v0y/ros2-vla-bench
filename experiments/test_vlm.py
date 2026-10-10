from transformers import pipeline
import os

local_path = os.path.dirname(os.path.abspath(__file__))
print(local_path)


pipe = pipeline(
    "image-text-to-text",
    model="Qwen/Qwen3-VL-2B-Instruct",
    device_map="auto",
)

messages = [
    {
        "role": "user",
        "content": [
            {
                "type": "image",
                "url": os.path.join(local_path, "room.png")
            },
            {
                "type": "text",
                    "text": """
                        You are controlling a mobile robot.

                        Choose exactly one action:
                        FORWARD
                        LEFT
                        RIGHT
                        STOP

                        Rules:
                        - FORWARD if the path directly ahead is clear.
                        - LEFT if an obstacle blocks the front and the left side looks clearer.
                        - RIGHT if an obstacle blocks the front and the right side looks clearer.
                        - STOP if you are unsure or the path looks unsafe.

                        Respond with only the action word.
                        """
            },
        ],
    }
]

result = pipe(
    text=messages,
    max_new_tokens=10,
)

print(result)
