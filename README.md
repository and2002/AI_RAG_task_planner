# AI_RAG_task_planner
Chatbot with plug in LLM for chatting and deplpying tasks to external memory. Requres LLM Studio with selected model to run. 
# File structure
Main directory 
|
|--- Main_chatbot_code.jl
|
|--- Memory (folder stores csv with task memory)  --- Task_memory.csv (Header: task_ID,task_priority,task_name,task_body,date_generated,date_deadline)
|
|--- Messages (folder stores chat folder) --- | --- Chat_1 (folder; custom name of the chat given by user) -- | --- chatbot.txt
                                              |                                                               | 
                                              |                                                               | --- user.txt
                                              |
                                              | --- .... (other chats)

# Interface description (Main Window)
First entry line - enter directory where message folders are stored. By default: Messages. To change - type new address and press button "Confirm home directory".
Main scroll area: here, all folders whith chats (all folders in directory sellected in the First line) are displayed.
Second entry line - select chat folder. Use buttons "UP" and "DOWN" to shift your choice in Main scroll area up and down respectively, once address of the correct chat folder appears in the Second entry line - press "SELECT". If you would like to create new Chat - enter name in the Second entry lane directly and press "SELECT"
# Interface Description (Chat Window)
Entry lane is for your messages. Type your message and press "Send"; wait AI to response. If you would like to save the chat history for future, press "Save".
# Work with task planner 
When you write message, you can force AI to perform 1 out of 3 main agent functions. 
1. You can ask it to remind you to do something by certain time (please be detailed); in addtion, it is recommended to privide numerical rating (how important the task is). Then AI would parce your request and save it into Task_memory.csv. You can check that file later to ensure that tasks were recorded correctly.
2. You can ask to remove task. Write a message with description which task you have completed and that task would be removed if it existed.
3. You can ask to recommend you a task from those are already on list in memory. Then AI would advice you which tasks to prioritise based on priority rating and deadline.
