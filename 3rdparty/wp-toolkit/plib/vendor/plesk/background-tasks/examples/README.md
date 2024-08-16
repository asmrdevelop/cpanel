This directory contains example usage of background task and could be used to check
how backend (PHP) part works.

Use:
1. `php init-database.php` to initialize SQLite database for storing database data.
2. `php add-task.php` to add simple test background task into database.
3. `php tasks-executor` to start executor which takes tasks from database and executes them.
Multiple instances of tasks-executor could be launched at the same time.
