<?php
// Copyright 1999-2020. Plesk International GmbH. All rights reserved.

class WhmAccessChecker
{
    const RESELLERS_ACL_FILEPATH = '/var/cpanel/resellers';
    const ROOT_USER_LOGIN = 'root';
    // Allow full access to WHM
    const FULL_PRIVILEGES_CODE = 'all';
    // Must be equal to acls inside whm-wp-toolkit.conf
    const REQUIRED_PRIVILEGES = [
        'list-accts',
    ];

    public function assertPermissions(): void
    {
        $currentUsername = $_ENV['REMOTE_USER'];
        if ($currentUsername === self::ROOT_USER_LOGIN) {
            return;
        }

        $resellersPrivileges = $this->readResellersAcls();
        if (!isset($resellersPrivileges[$currentUsername])) {
            throw new \Exception("Unable to find reseller with username '{$currentUsername}' inside " . self::RESELLERS_ACL_FILEPATH);
        }

        $currentResellerPrivileges = $resellersPrivileges[$currentUsername];
        if (in_array(self::FULL_PRIVILEGES_CODE, $currentResellerPrivileges)) {
            return;
        }

        $diff = array_diff(self::REQUIRED_PRIVILEGES, $currentResellerPrivileges);
        if (empty($diff)) {
            return;
        }

        throw new \Exception(
            "You do not have all required permissions to access WP Toolkit. " .
            "Please contact your provider and request following permissions: " .
            implode(", ", $diff)
        );
    }

    /**
     * @see \PleskExt\WpToolkit\Service\Cpanel\User\CpanelUserTypeHelper::readResellersAcls() duplicated code
     * @return array [ resellerUsername => [ privilege1, privilege2 ] ]
     * @throws Exception
     */
    private function readResellersAcls(): array
    {
        if (!file_exists(self::RESELLERS_ACL_FILEPATH)) {
            throw new \Exception("Unable to find file with resellers privileges: " . self::RESELLERS_ACL_FILEPATH);
        }

        $fileContent = file_get_contents(self::RESELLERS_ACL_FILEPATH);
        if ($fileContent === false) {
            throw new \Exception("Unable to read file with resellers privileges: " . self::RESELLERS_ACL_FILEPATH);
        }

        $resellersPrivileges = [];
        foreach (explode("\n", $fileContent) as $line) {
            $parts = explode(":", $line, 2);
            if (count($parts) !== 2) {
                continue;
            }
            list($resellerUsername, $resellerPrivilegesAsString) = $parts;
            $resellersPrivileges[$resellerUsername] = explode(",", $resellerPrivilegesAsString);
        }

        return $resellersPrivileges;
    }
}
