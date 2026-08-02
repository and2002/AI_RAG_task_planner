# libraries
using Gtk4
using Dates
using HTTP
using JSON3
using CSV
using DataFrames

# Structures
struct message_structure # this structure stores message
    message_ID::Int64
    message_date::DateTime
    message_body::String
end

# variables for main window
selected_index = 1 # currently selected folder in home directory (by index)
saved_address = "" # address of that folder
current_children = String[] # array of children in the main directory
child_labels = GtkLabel[] # array of labels of corresponding childen to display them
current_directory = joinpath(@__DIR__, "Messages") # address of the directory where chat folders live

# global variables for chat window
global task_data_base_file_adress  = joinpath(@__DIR__,"Memory","Task_memory.csv") # address of task memory file
global chatbot_messages # array of structures for bot messages
global user_messages # array of structures for user messages
global initial_prompt = """You have access to functions.

Available functions:

1. print_llm(text)

If user asks to print something,
respond ONLY in JSON:

{"message":"text","function":"print_llm","argument":{"word":"..."} }
where 'text' is a responce, '...' - what you think user asked to print
Example:
user types: 'print result of 4-3 into output'
your output will be:{"message":"result is 1","function":"print_llm","argument":{"word":"1"}}

2. record_task(task_ID, task_name, task_body, date_generated, date_deadline) 

If user asks you to remind them to do something,
respond ONLY in JSON:
{"message":"text","function":"record_task","argument":{"task_ID": "place here random positive integer number that didn't occur in context before","task_priority":"positive integer that represents priority; for tasks that user marks as priority or whose deadline is soon or they are time consuming priority is higher","task_name":"brief title for the task user wants remainder for","task_body":"plase here what task itself is","date_generated":"most recent date icorporated before your response in format YYYY-MM-DDTHH:MM:SS","date_deadline":"the time by which task should be finish according to user in format YYYY-MM-DDTHH:MM:SS"}}
If some information is missing, assign task_ID to 0 and put in "text" message to clarify user what they meant.
Example:
user types: 'please remind me to buy a postcard for a friend by the 20 th of July.' Most recent date in chat - 2026-07-11T21:07:06
your output will be:
{"message":"your remainder was added. Hope you get a nice postcard!","function":"record_task","argument":{"task_ID": "120733","task_priority":"10","task_name":"postcard","task_body":"buy postcard for friend","date_generated":"2026-07-11T21:07:06","date_deadline":"2026-07-20T23:59:59"}}

3. remove_task(task_ID)
If user asks you to remove task because it is completed or irrelevant,
respond ONLY in JSON:
{"message":"text","function":"remove_task","argument":{"task_ID":"place here positive integer number that represents the task user asked to delete, eiter by direct ruquest, either by context. If there is no such task, put 0"}}
Example 1:
user types: 'pease remove task 487: I have completed it'
your output will be:
{"message":"glad that you have completed task 487! It has been removed.","function":"remove_task","argument":{"task_ID":"487"}}
Example 2:
user types: 'I have bought a beach chair. Can you remove the task?" ; context has task "buy a beach chair" that has task_ID 128
your output will be:
{"message":"glad that you have bought that chair! The task 128 has been removed.","function":"remove_task","argument":{"task_ID":"128"}}

4. advise_task()
If user asks you to advice them tasks, list a few tasks that have close deadline (less than 2 days from current time) and/or have high priority
"""

# functions
function list_current_directory(path::String) # function lists all elements in the folder or throws error

    if !ispath(path)
        error("check or confirm directory")
    end

    return readdir(path)
end

function process_chat_directory( path:: String) # function takes adress of the chat folder. If folder exists, it checks if user and chatbot files exists. If not, creates
    
    if !ispath(path) # if folder with chat doesn't exist, create it
        mkdir(path)
    end

    chatbot_path = joinpath(path, "chatbot.txt") # adress of the chatbot
    user_path = joinpath(path, "user.txt") # address of user answers

    entry_message_chatbot = "=>1=:=2026-01-01T00:00:01\n&\nHello!\n=<1\n" # message that will be recorded into chatbot text file by default

    if !isfile(chatbot_path) # if there is no file for chatbot, create it and write default message
        open(chatbot_path, "w") do io
            println(io, entry_message_chatbot)
        end
    end

    if !isfile(user_path) # if there is no file for chatbot, create it and write default message
        open(user_path, "w")
    end

    return chatbot_path, user_path # return addresses
end

function read_task_list() # function returns task_data_base as data frame read from pre defined file
    global task_data_base_file_adress # load global variable where adress is stored
    task_data_base = CSV.read(task_data_base_file_adress, DataFrame; types = [Int64, Int64, String, String, DateTime, DateTime])
    return task_data_base
end

function write_task_list(task_data_base::DataFrame) # function takes task_data_frame and writes it into predefined address
    global task_data_base_file_adress # load global variable where adress is stored
    CSV.write(task_data_base_file_adress, task_data_base)
end

function form_context_from_task_data_base() # function teturns text formatted to be loaded into context window
    global task_data_base_file_adress # load global variable where adress is stored
    task_data_base = CSV.read(task_data_base_file_adress, DataFrame; types = [Int64, Int64, String, String, DateTime, DateTime])
    number_of_tasks = nrow(task_data_base) # get number of tasks
    context_text = "Task list:\n"
    for i = 1:number_of_tasks
        context_text = context_text * "===Entry_" * string(i) * "===\n" # title, then entrances for each column
        context_text = context_text * "task_ID-" * string(i) * ":" * string(task_data_base.task_ID[i]) * "\n" 
        context_text = context_text * "task_priority-" * string(i) * ":" * string(task_data_base.task_priority[i]) * "\n"
        context_text = context_text * "task_name-" * string(i) * ":" * string(task_data_base.task_name[i]) * "\n"
        context_text = context_text * "task_body-" * string(i) * ":" * string(task_data_base.task_body[i]) * "\n"
        context_text = context_text * "date_generated-" * string(i) * ":" * string(task_data_base.date_generated[i]) * "\n"
        context_text = context_text * "date_deadline-" * string(i) * ":" * string(task_data_base.date_deadline[i]) * "\n"
    end
    return context_text # return result
end
function list_all_positions_of_substring_in_string(substring::String, main_string::String)::Vector{Int} # find all positions of string substing in string main_string, retun vector Int
    positions = Int[] #create blank array
    
    if isempty(substring) || isempty(main_string) # check if any of them is empty
        return positions
    end

    position_of_substring = findfirst(substring, main_string) # calculate the first postion of sub_string

    while !isnothing(position_of_substring) # until position is not empty, search for next one
        push!(positions, first(position_of_substring)) # record position that already found
        position_of_substring = findnext(substring, main_string, nextind(main_string, first(position_of_substring))) # try to find the next one after last one found
    end

    return positions # retun the result
end

function check_message_file_structure(text_file::String) # function takes text of files and checks if messages there have required structure
    number_of_messages = length(list_all_positions_of_substring_in_string("=>", text_file)) # get number of messages

    message_starters_positions = list_all_positions_of_substring_in_string("=>", text_file) # get positions of messages starters
    message_date_positions = list_all_positions_of_substring_in_string("=:=", text_file) # get positions of dates in messages
    message_open_positions = list_all_positions_of_substring_in_string("&", text_file) # get positions of dates in messages
    message_close_positions = list_all_positions_of_substring_in_string("=<", text_file) # get positions of dates in messages

    # perform checks

    # check 1: length match. lengths of all arrays should be same
    if length(message_starters_positions) != length(message_date_positions) || length(message_starters_positions) != length(message_open_positions) || length(message_starters_positions) != length(message_close_positions)
        return false
    end

    #check 2: check for order. Start-date-open-close
    for i in 1:number_of_messages
        if ((message_starters_positions[i] < message_date_positions[i]) && (message_date_positions[i] < message_open_positions[i]) && (message_open_positions[i] < message_close_positions[i])) != true
            return false
        end
    end

    return true
end

function parse_message_with_given_number(text_file::String, message_number) # function takes message file and number of message to read
    
    message_starters_positions = list_all_positions_of_substring_in_string("=>", text_file) # get positions of messages starters
    message_date_positions = list_all_positions_of_substring_in_string("=:=", text_file) # get positions of dates in messages
    message_open_positions = list_all_positions_of_substring_in_string("&", text_file) # get positions of dates in messages
    message_close_positions = list_all_positions_of_substring_in_string("=<", text_file) # get positions of dates in messages

    message_ID = text_file[message_starters_positions[message_number] + 2 : message_date_positions[message_number] - 1] # get id of the message
    message_date = text_file[message_date_positions[message_number] + 3 : message_open_positions[message_number] - 3] # get date of the message
    message_body = text_file[message_open_positions[message_number] + 2 : message_close_positions[message_number] - 2] # get message message_body
    
    message = message_structure(parse(Int64, message_ID), parse(DateTime, message_date), message_body) # record into structure
    return message
end

function read_message_file(message_file_adress::String) # function takes file adress and parses it to structure message
    # TODO implement checks of file existance and readability
    text_file = read(message_file_adress, String) # get text of file
    number_of_messages = length(list_all_positions_of_substring_in_string("=>",text_file)) # get number of messages
    message_list = message_structure[] # empty list for messages to be pushed to

    # check if file is okay
    if check_message_file_structure(text_file)

        # if yes - then go through all messages
        for i = 1:number_of_messages 
            message = parse_message_with_given_number(text_file, i)
            push!(message_list, message)
        end
        
    end
    return message_list
end

function write_message_file(message_file_adress::String, message_array) # function takes message array and writes it to message_file
    # TODO implement checks of file existance and readability
    number_of_messages = length(message_array) # get number of messages
    text_file = "" # empty text file

    if number_of_messages < 1 # do nothing if empty
        return
    end

    for i = 1:number_of_messages # if messages exist, then write
        text_file = text_file * "=>" * string(message_array[i].message_ID) * "=:=" * string(message_array[i].message_date) * "\n&\n" * string(message_array[i].message_body) * "\n=<" * string(message_array[i].message_ID) * "\n"
    end

    write(message_file_adress, text_file)
end

function generate_response() # function takes message arrays and generates response
    # gloabal variables to check
    global chatbot_messages
    global user_messages
    # something will be there

    # prepare main stuff
    chatbot_new_message_date = now()
    chatbot_message_id = 0 # default number

    if isempty(chatbot_messages) # if exists, then next. If not, just 1
        chatbot_message_id = 1
    else
        chatbot_message_id = chatbot_messages[end].message_ID + 1
    end

    prompt = build_prompt() # compress messages to promt
    chatbot_message_body = ask_llm(prompt) # put promt into LLM and get response

    # load to chatbot message array
    new_chatbot_message = message_structure(chatbot_message_id, chatbot_new_message_date, chatbot_message_body) # assemble to message structure
    push!(chatbot_messages, new_chatbot_message)

    return chatbot_messages
end

function build_prompt() # function that creates promt for LLM

    # load global variables
    global chatbot_messages
    global user_messages
    global initial_prompt

    prompt = initial_prompt
    prompt = prompt * form_context_from_task_data_base() # add 
    # measure length of message arrays
    number_of_messages_chatbot = length(chatbot_messages)
    number_of_messages_user = length(user_messages)
    max_messages = max(number_of_messages_chatbot, number_of_messages_user) #maximum number of messages

    for i = 1:max_messages # one by one construct promt

        if i <= length(user_messages)
            prompt *= "User said: " * user_messages[i].message_body * "\n Date: " * string(user_messages[i].message_date) * "\n"
        end

        if i <= length(chatbot_messages)
            prompt *= "Assistant said: " * chatbot_messages[i].message_body * "\n Date: " * string(chatbot_messages[i].message_date) * "\n"
        end

    end

    prompt *= "Assistant:"

    return prompt
end

function ask_llm(prompt)  # fucntion creates responce to promt via LLM

    body = Dict(
        "model" => "local-model",
        "messages" => [
        Dict(
            "role" => "user",
            "content" => prompt
            )
        ],
        "temperature" => 0.7
    )

    response = HTTP.post("http://127.0.0.1:1234/v1/chat/completions", ["Content-Type" => "application/json"], JSON3.write(body))
    object = JSON3.read(String(response.body)) # get response itself
    text_back_to_chat = llm_response_parse(object) 
    return text_back_to_chat
end

function repair_json(text::String) # function takes on input something that can be JSON and replaces symbols that are there by accident

    # Replace single quotes with double quotes
    text = replace(text, "','" => "\",\"")
    text = replace(text, ",'" => ",\"")
    text = replace(text, "'," => "\",")
    text = replace(text, ":'" => ":\"")
    text = replace(text, "':" => "\":")
    # Remove trailing commas before } or ]
    text = replace(text, r",\s*}" => "}")
    text = replace(text, r",\s*]" => "]")

    return text

end

function llm_response_parse(object) # function takes LLM responce as object (look to function ask_llm) and checks if it has agent functions. if yes, calls them. otherwise, returns message content

    # get JSON/text returned by the model
    content = object.choices[1].message.content
    content = repair_json(content) # filter out
    
    try
        # try to interpret it as JSON command
        obj = JSON3.read(content) 

        if haskey(obj, :function) # check if function was called

            println("function detected")
            println(obj)
            if obj.function == "print_llm" # check for function print_llm
                try
                    print_llm(obj.argument.word)
                catch err # if fails, thow error
                    println("print_llm failed:")
                    println(err)
                end
            end

            if obj.function == "record_task" # check for function record_task
                try
                    record_task(
                        parse(Int64, obj.argument.task_ID),
                        parse(Int64, obj.argument.task_priority),
                        obj.argument.task_name,
                        obj.argument.task_body,
                        parse(DateTime, obj.argument.date_generated),
                        parse(DateTime, obj.argument.date_deadline)
                    )
                catch err # if fails, thow error
                    println("record_task failed:")
                    println(err)
                end
            end

            if obj.function == "remove_task" # check for function record_task
                try
                    remove_task(parse(Int64, obj.argument.task_ID))
                catch err # if fails, thow error
                    println("remove_task failed:")
                    println(err)
                end
            end
        end

        if haskey(obj, :message) # return message field if present    
            println("message is here")
            return obj.message
        end

    catch
        # not JSON -> treat as ordinary text
    end

    

    return content

end

function print_llm(message::String) # test function to check how agent function works: simple print
    println("LLM print: ", message)
end

function record_task(task_ID:: Int64, task_priority:: Int64, task_name:: String, task_body:: String, date_generated::DateTime, date_deadline :: DateTime) # function saves 
    println("record_task was triggered. Results below:")
    
    task_data_base = read_task_list()  # read existing data base
    push!(task_data_base, [task_ID, task_priority, task_name, task_body, date_generated, date_deadline]) # record to data base
    write_task_list(task_data_base) # record changes
    task_upd = read_task_list()
    println(task_upd)
end

function remove_task(task_ID::Int64) # function takes number of task and deletes it from data base
    task_data_base = read_task_list()  # read existing data base
    filter!(row -> row.task_ID != task_ID, task_data_base) # remove task from the data base
    write_task_list(task_data_base) # record it back
end

function display_main_widget() # creation of main widget
    
    # box itself
    win = GtkWindow("Directory Selector", 700, 500) 
    main_box = GtkBox(:v, 10)
    push!(win, main_box)

    # create top entry line for address of home directory where chats are stored
    top_box = GtkBox(:h, 5)
    push!(main_box, top_box)

    # path entry
    entry_directory = GtkEntry() # sets entry line for top box
    entry_directory.hexpand = true # sets it to be expandable
    set_gtk_property!(entry_directory, :text, current_directory) # fills it in with default text: current directory adress
    push!(top_box, entry_directory) # load it into window

    # confirm button: confirms selection of address of home directory where chats are stored
    confirm_button = GtkButton("Confirm home directory")
    push!(top_box, confirm_button)

    # create scrollable area
    child_scroll_area = GtkScrolledWindow() # create scrollable section for displaying children
    child_scroll_area.hscrollbar_policy = Gtk4.PolicyType_NEVER # allow scrolling vertically
    child_scroll_area.vscrollbar_policy = Gtk4.PolicyType_ALWAYS # don't allow scrolling horisontally
    child_scroll_area.vexpand = true # allow it to be expandable vertically
    child_scroll_area.hexpand = true # allow it to be expandable vertically
    push!(main_box, child_scroll_area) # load to main section

    # actually set of lables that will contain labels
    children_box = GtkBox(:v, 3) 
    child_scroll_area[] = children_box 
 
    # displays currently selected chat folder for selection
    bottom_box = GtkBox(:h, 5)
    push!(main_box, bottom_box)

    # child entry (child folders)
    entry_child_name = GtkEntry() # gets child name section
    entry_child_name.hexpand = true # make it expandable
    push!(bottom_box, entry_child_name)

    # define special box for buttons
    buttons_box = GtkBox(:h, 5)
    push!(main_box, buttons_box)

    # define buttons
    up_button = GtkButton("UP")
    down_button = GtkButton("DOWN")
    select_button = GtkButton("SELECT")

    # load buttons into buttons
    push!(buttons_box, up_button)
    push!(buttons_box, down_button)
    push!(buttons_box, select_button)

    function reload_directory(path) # function reloads directory each time select is pressed

        global current_children

        try

            current_children_local = list_current_directory(path) # get array of all children in the directory

        catch err # check if any error happens

            clear_child_scroll_area() # clear child scroll area since we renewed main directory
            lbl = GtkLabel("check or confirm directory") # create an error label
            push!(children_box, lbl) # throw an error label
            push!(child_labels, lbl) # save to external array as well

        else # error didn't happen so we can load existing children (if any)
            clear_child_scroll_area() # clear all rubbish that may be there
            current_children = list_current_directory(path) # get array of all children in the directory
            println(current_children)
            load_children_to_child_scroll_area(current_children) # reload child list
        end

    end

    function clear_child_scroll_area() # fuction clears all entrances in child_scroll_area
        
        for lbl in child_labels # go for each label and delete it from child_scroll_area
            delete!(children_box, lbl)
        end

        empty!(child_labels) # clear the external array itself
    end

    function load_children_to_child_scroll_area(current_children) # function takes array that includes all children and loads them into child_scroll_area
        
        global current_children
        
        empty!(child_labels) # reset the array of labels

        for child in current_children
            #println(child)
            lbl = GtkLabel(string(child)) # create label for child
            push!(child_labels, lbl) # load label to external array
            push!(children_box, lbl) # load to child_scroll_area
        end

    end

    function set_selected_child(child_name) # function takes name of the child and pushes to the corresponding box
        set_gtk_property!(entry_child_name, :text, child_name) # fills it in with default text: currently selected child
    end

    # confirm button action connection
    signal_connect( confirm_button, "clicked") do widget # action reloads to the variable path whatever string entered into the top field

        path = get_gtk_property( entry_directory, :text, String)
        reload_directory(path) # trigger the whole process of updating
    end

    # up button action connection
    signal_connect(up_button,"clicked") do widget # connect action to widget
        
        global current_children
        global selected_index

        print(current_children)
        if isempty(current_children) # if no children, do nothing
            return
        end

        if selected_index == 1 # go up, from top -> bottom
            selected_index = length(current_children)
        else
            selected_index -= 1
        end

        #println("UP--",selected_index)
        set_selected_child(current_children[selected_index]) # update text what appears at the bottom entrance field
    end

    # down button action connection
    signal_connect(down_button, "clicked") do widget

        global current_children
        global selected_index

        if isempty(current_children) # if no children, do nothing
            return
        end

        if selected_index == length(current_children) # go down, from very down -> up
            selected_index = 1
        else
            selected_index += 1
        end

        #println("DOWN--",selected_index)
        set_selected_child(current_children[selected_index]) # update text what appears at the bottom entrance field
    end

    # select button action connection
    signal_connect(select_button, "clicked") do widget

        child_name = get_gtk_property(entry_child_name, :text, String) # scan name back from the bottom box
        saved_address = joinpath(current_directory, child_name) # assemble into the file adress

        # print the result
        println()
        println("Saved address:")
        println(saved_address)
        chatbot_responses_file_adress, user_messages_file_adress = process_chat_directory(saved_address)
        display_main_chat_widget(chatbot_responses_file_adress, user_messages_file_adress) # open next widget
    end

    reload_directory(current_directory) # load directory for the first time

    show(win) # show main window

    return win
end

function display_main_chat_widget(chatbot_responses_file_adress::String, user_messages_file_adress::String) # fucntion displays main chat

    # functions
    function load_history_messages() # function loads past messages from both files
        global chatbot_messages 
        global user_messages 
        println(user_messages)
        println(chatbot_messages)
        # measure length of message arrays
        number_of_messages_chatbot = length(chatbot_messages)
        number_of_messages_user = length(user_messages)
        max_messages = max(number_of_messages_chatbot, number_of_messages_user) #maximum number of messages

        for i = 1:max_messages # go through all messages

            if i < number_of_messages_chatbot + 1 # if we have chatbot messages, then display (by default, we start with hello message from chatbot)
                chatbot_message_label = GtkLabel(chatbot_messages[i].message_body)
                chatbot_message_label.halign = Gtk4.Align_START
                chatbot_message_label.margin_start = 60   # push it away from the left
                push!(messages_box, chatbot_message_label)
                show(chatbot_message_label)
            end

            if i < number_of_messages_user + 1 # if we have user messages, then display
                user_message_label = GtkLabel(user_messages[i].message_body)
                user_message_label.halign = Gtk4.Align_END
                user_message_label.margin_start = 60   # push it away from the left
                push!(messages_box, user_message_label)
                show(user_message_label)
            end
        end
    end
    
    function record_new_message() # function activated by the click of button "Save'

        global chatbot_messages
        global user_messages
        new_user_message_text = entry.text # read new user message

        if !isempty(new_user_message_text) # if message is not empty, process

            new_user_message_date = now() # request current time
            new_user_message_ID = 0 # default number

            if isempty(user_messages) # if exists, then next. If not, just 1
                new_user_message_ID = 1
            else
                new_user_message_ID = user_messages[end].message_ID + 1
            end
            new_user_message_structure = message_structure(new_user_message_ID, new_user_message_date, new_user_message_text)  # form into sturcture
            push!(user_messages, new_user_message_structure)  # load message to array of whole user messages

            # push last (that new user message) to message box
            user_message_label = GtkLabel(user_messages[end].message_body)
            user_message_label.halign = Gtk4.Align_END
            user_message_label.margin_start = 60   # push it away from the left
            push!(messages_box, user_message_label)
            show(user_message_label)

            # pass exisiting messages to generate response 
            chatbot_messages = generate_response() # generate message based on past context
            chatbot_message_label = GtkLabel(chatbot_messages[end].message_body)
            chatbot_message_label.halign = Gtk4.Align_START
            chatbot_message_label.margin_start = 60   # push it away from the left
            push!(messages_box, chatbot_message_label)
            show(chatbot_message_label)

        end

        entry.text = "" # free up entry section for future text
    end

    function save_messages_into_file(chatbot_messages_file_adress::String, user_messages_file_adress::String) #function saves messages to the corresponding files, takes adresses for chatbot and user files to write there
        
        # load global variables
        global chatbot_messages 
        global user_messages
        # 
        write_message_file(chatbot_messages_file_adress, chatbot_messages)
        write_message_file(user_messages_file_adress, user_messages)
    end
    # load message arrays
    global chatbot_messages = read_message_file(chatbot_responses_file_adress)
    global user_messages = read_message_file(user_messages_file_adress)

    # form main window
    win = GtkWindow("Chat window", 700, 500)
    main_box = GtkBox(:v, 10)
    push!(win, main_box)

    # Add a messages box above the entry — this will grow as conversation goes
    messages_box = GtkBox(:v, spacing=6)
    messages_box.margin_bottom = 10

    vbox = GtkBox(:v, spacing=10)
    vbox.margin_top    = 80
    vbox.margin_bottom = 20
    vbox.margin_start  = 20
    vbox.margin_end    = 20

    entry = GtkEntry() # create entry line where users can print their messages
    entry.placeholder_text = "Type here..."

    send_button = GtkButton("Send") # create a send button
    save_button = GtkButton("Save") # create an save button

    # add elements to vbox
    push!(vbox, messages_box)   # chat history goes here
    push!(vbox, entry)
    push!(vbox, send_button)
    push!(vbox, save_button)

    # make it scrollable and add to main widget
    scroll = GtkScrolledWindow()
    scroll.hscrollbar_policy = Gtk4.PolicyType_NEVER
    scroll.vscrollbar_policy = Gtk4.PolicyType_ALWAYS
    scroll[] = vbox

    win[] = scroll
    
    
    # load history message
    load_history_messages()
    # once history is loaded then recive new messages
    signal_connect(send_button, "clicked") do widget
        record_new_message()
    end

    # when user wants, save messages
    signal_connect(save_button, "clicked") do widget
        save_messages_into_file(chatbot_responses_file_adress, user_messages_file_adress) # save files
    end
end

display_main_widget()