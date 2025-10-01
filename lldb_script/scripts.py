import shlex

def bcond(debugger, command, result, internal_dict):
    parts = shlex.split(command)
    if len(parts) != 2:
        result.PutCString("Need two args: name of the function, and the condition in quotes")
    # parts[0] is what comes after name "bcond" i.e. bond parts[0] parts[1]
    funcname, cond = parts
    cmd = f"breakpoint set --name {funcname} --condition \"{cond}\""
    debugger.HandleCommand(cmd)

def lcond(debugger, command, result, internal_dict):
    parts = shlex.split(command)
    if len(parts) != 3:
        result.PutCString("Need 3 args: name of the file, line number, and the condition")
    filename, lineno, cond = parts
    debugger.HandleCommand(f"breakpoint set --file {filename} --line {lineno} --condition \"{cond}\"")
