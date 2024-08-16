<?php
// Copyright 1999-2018. Plesk International GmbH. All rights reserved.

date_default_timezone_set(@date_default_timezone_get());

// allow to execute tests from any directory
chdir(__DIR__);

require_once(__DIR__ . '/../vendor/autoload.php');
