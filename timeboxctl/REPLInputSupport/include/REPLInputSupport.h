#pragma once

/* Call only while holding the application's exclusive editor lock. */
int timebox_repl_install_input_hook(void);
int timebox_repl_remove_input_hook(void);
