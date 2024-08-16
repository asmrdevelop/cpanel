<?php
// Copyright 1999-2020. Plesk International GmbH. All rights reserved.

class WhmMainPage implements MainPageInterface
{
    /**
     * @var WhmAccessChecker
     */
    private $accessChecker;

    public function __construct(WhmAccessChecker $accessChecker)
    {
        $this->accessChecker = $accessChecker;
    }

    public function checkConstraints(): void
    {
        $this->accessChecker->assertPermissions();

        if ($_SERVER['HTTPS'] !== 'on') {
            throw new \Exception('Allowed only for secured HTTPS connections');
        }
    }

    public function getCpanelHeader(): string
    {
        ob_start();
        WHM::header('', 0, 0);
        return ob_get_clean();
    }

    public function getCpanelFooter(): string
    {
        ob_start();
        WHM::footer();
        return ob_get_clean();
    }

    public function isCpanel(): bool
    {
        return false;
    }
}
