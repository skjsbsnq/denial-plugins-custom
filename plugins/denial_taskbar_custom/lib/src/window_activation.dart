/// A focused, visible window toggles to minimized; other windows are raised.
bool shouldMinimizeWindow({required bool active, required bool minimized}) =>
    active && !minimized;
