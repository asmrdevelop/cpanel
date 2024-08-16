<?php
// Copyright 1999-2020. Plesk International GmbH. All rights reserved.

interface MainPageInterface
{
    public function checkConstraints(): void;

    public function getCpanelHeader(): string;

    public function getCpanelFooter(): string;

    public function isCpanel(): bool;
}
