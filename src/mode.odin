package main

Mode :: enum {
    Normal,
    Insert,
    Replace,
    Visual_Char,
    Visual_Line,
    Visual_Block,
    Operator_Pending,
    Command,
    Search_Forward,
    Search_Backward,
    Insert_Completion,
}
