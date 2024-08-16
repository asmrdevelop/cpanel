<?php
// Copyright 1999-2020. Plesk International GmbH. All rights reserved.

class CpanelMainPage implements MainPageInterface
{
    private const APP_KEY = 'wordpress-toolkit';
    /**
     * @var CPANEL
     */
    private $cpanel;

    /**
     * @param CPANEL $cpanel
     */
    public function __construct($cpanel)
    {
        $this->cpanel = $cpanel;
    }

    public function checkConstraints(): void
    {
        if ($_SERVER['HTTPS'] !== 'on') {
            throw new \Exception('Allowed only for secured HTTPS connections');
        }
    }

    public function getCpanelHeader(): string
    {
        return $this->cpanel->header('', self::APP_KEY);
    }

    public function getCpanelFooter(): string
    {
        return $this->cpanel->footer();
    }

    public function isCpanel(): bool
    {
        return true;
    }
}
