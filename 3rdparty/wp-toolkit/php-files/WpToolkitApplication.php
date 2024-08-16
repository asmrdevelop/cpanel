<?php
// Copyright 1999-2020. Plesk International GmbH. All rights reserved.

class WpToolkitApplication
{
    /**
     * @var MainPageInterface
     */
    private $mainPage;

    /**
     * @var bool
     */
    private $debug = false;

    public function __construct(MainPageInterface $mainPage)
    {
        $this->mainPage = $mainPage;
    }

    public function run(): void
    {
        try {
            $this->mainPage->checkConstraints();

            MemoryLogger::getInstance()->log('Start compose page HTML');
            $pageHeader = $this->mainPage->getCpanelHeader();
            $pageFooter = $this->mainPage->getCpanelFooter();
            $pageContents = $this->getTemplate();
            MemoryLogger::getInstance()->log('End compose page HTML');

            $debugContents = $this->getDebugHtml();

            echo $pageHeader . $pageContents . $debugContents . $pageFooter;
        } catch (\Exception $exception) {
            http_response_code(500);
            echo $exception->getMessage();
        }
        die();
    }

    private function getTemplate(): string
    {
        $assetVersion = $this->getAssetVersionQuery();
        $urls = json_encode([
            'apiUrl' => $this->getApiUrl(),
            'restApiUrl' => $this->getRestApiUrl()
        ]);

        $pageHtml = <<<HTML
<link rel="stylesheet" href="main.css{$assetVersion}" />
<script src="app.bundle.js{$assetVersion}"></script>
<div id="main"></div>

<script>
wptCpanelMain.default({$urls});
</script>
HTML;
        return $pageHtml;
    }

    private function getDebugHtml()
    {
        if (!$this->debug) {
            return '';
        }

        $jsonEncodedLog = json_encode(MemoryLogger::getInstance()->getMessages(), JSON_PRETTY_PRINT);
        return <<<HTML
<script>
{$jsonEncodedLog}.forEach(
    function(logEntry) {
        window.console.log("[WPT plugin] " + logEntry);
    }
);
</script>
HTML;
    }

    private function getAssetVersionQuery(): string
    {
        $assetVersionQuery = '';
        $buildFileContents = file_get_contents('/usr/local/cpanel/3rdparty/wp-toolkit/build.json');
        if ($buildFileContents !== false) {
            $buildInfo = json_decode($buildFileContents, true);
            if (is_array($buildInfo) && isset($buildInfo['version']) && isset($buildInfo['buildNumber'])) {
                $assetVersionQuery = '?' . $buildInfo['version'] . '-' . $buildInfo['buildNumber'];
            }
        }
        return $assetVersionQuery;
    }

    private function getApiUrl(): string
    {
        return $this->mainPage->isCpanel() ? '/3rdparty/wpt/index.php?action=' : '/cgi/wpt/index.php?action=';
    }

    private function getRestApiUrl(): string
    {
        $path = $this->mainPage->isCpanel() ? '3rdparty' : 'cgi';
        $action = $this->isUrlWithAction() ? '?action=' : '';

        return "/{$path}/wpt/index.php{$action}";
    }

    private function getPanelVersion(): string
    {
        $version = trim(file_get_contents('/usr/local/cpanel/version'));
        return preg_replace('/^11\./', '', $version);
    }

    private function isUrlWithAction(): bool
    {
        return version_compare($this->getPanelVersion(), '102.0.24', '<');
    }
}
