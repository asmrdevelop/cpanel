<?php
// Copyright 1999-2019. Plesk International GmbH. All rights reserved.

namespace BackgroundTaskExamples;
use PDO;

function createSqlitePdo()
{
    return new PDO('sqlite:tasks.sqlite3');
}
