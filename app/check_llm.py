"""Step 2: LLM 연결만 확인합니다."""
import os
from dotenv import load_dotenv
from langchain.chat_models import init_chat_model

load_dotenv()
llm = init_chat_model(os.environ["LLM_MODEL"])
print(llm.invoke("한 문장으로 인사해줘.").content)
