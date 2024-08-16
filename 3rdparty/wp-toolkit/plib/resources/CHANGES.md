# 6.5.1 (18 Jul 2024)

* [-] (cPanel) WP Toolkit no longer prevents packages and accounts from being modified on cPanel v110. (EXTWPTOOLK-12068)

# 6.5.0 (17 Jul 2024)

* [+] WP Guardian addon with Vulnerability Protection can now be purchased for individual WordPress sites
	* This addon can be purchased directly by any control panel user, including end-users (site administrators), for any WordPress site they can access in WP Toolkit
	* On Plesk, single-site WP Guardian addon does not include other Deluxe features like Smart Updates or Smart PHP Updates
	* Sites using this addon do not count towards Vulnerability Protection limit in service plans, subscriptions, or packages
	* The ability for users to buy this addon cannot be restricted via Vulnerability Protection limit in service plans, subscriptions, or packages
	* If server-level WP Guardian addon license is already present on the server, the ability to buy a single-site addon is automatically disabled
	* To enable or disable this offer, add the following parameter in `panel.ini` (Plesk) or `config.ini` (cPanel) file and set its value to 1 or 0: `virtualPatchesLicensingForEndCustomers`
	* This offer will be made available selectively and gradually to make sure server administrators have enough time to disable it, if needed
* [+] Actively exploited vulnerabilities now have their own `Critical` risk rank
* [*] Codeable integration now tracks server ownership for the upcoming affiliate program
* [*] WP Toolkit now greys out addressed vulnerabilities to help users focus on the non-addressed ones
* [*] Additional hints will be shown to server administrators who try to enable Vulnerability Protection without adding it to a service plan, subscription, or package
* [-] Assets are no longer marked as vulnerable when all their vulnerabilies are already addressed. (EXTWPTOOLK-11943)
* [-] Incorrect mitigation options are no longer shown for certain vulnerabilities in WordPress core. (EXTWPTOOLK-11923)
* [-] Site search now properly finds sites located on a non-current site list pages (if you have that many sites). (EXTWPTOOLK-11620)
* [-] `Install` button on certain screens no longer remains active after a plugin or a theme are installed. (EXTWPTOOLK-11559)
* [-] (cPanel) WP Toolkit no longer prevents administrators from editing packages if API logging is enabled on a server. (EXTWPTOOLK-11882)
* [-] (Plesk) Security management feature is once again no longer available to users without a corresponding Service Plan permission. (EXTWPTOOLK-11793)

# 6.4.2 (21 Jun 2024)

* [-] (cPanel) WP Toolkit no longer fails to install with `Initial data load error: some required fields are not provided` error under certain circumstances. (EXTWPTOOLK-11905)

# 6.4.1 (20 Jun 2024)

* [-] Vulnerability database update no longer fails with error `Allowed memory size of 268435456 bytes exhausted`. (EXTWPTOOLK-11883)
* [-] Fixed inability to install new WordPress that could be caused by the above bug. (EXTWPTOOLK-11884)
* [-] (Plesk) Curious server admins should no longer see `VirtualPatchesLicensing::updateCpanelLicense was called on unsupported platform` error in the `panel.log`. (EXTWPTOOLK-11874)

# 6.4.0 (11 Jun 2024)

* [+] Introducing Vulnerability Protection: a new security feature for WordPress websites provided as a part of WP Guardian offer. Vulnerability protection is a non-invasive, automated, lightweight way to neutralize vulnerabilities in WordPress plugins, themes, and WordPress core. Once enabled on a site, vulnerability protection neutralizes high and medium risk vulnerabilities automatically whenever they appear without any need for user engagement.
	* A WordPress plugin will be installed when protection is enabled to automatically neutralize dangerous vulnerabilities by applying special protection rules.
	* Protection rules work like a firewall, so they never touch or modify the site code.
	* Protection rules are applied and removed only for specific vulnerabilities on any given site, so they have minimal effect on site performance.
	* This feature and its corresponding upsell prompts are not visible to control panel users by default. Only the server administrator can see it.
	* You can control the access to this feature via separate limit in your Service Plans (Plesk) or Packages (cPanel).
	* Vulnerability protection is a part of the security suite provided by WP Guardian platform. It requires purchasing a separate license called either WP Guardian (Plesk addon) or WP Guardian (cPanel addon), depending on your control panel. 
	* WP Guardian (Plesk addon) is an upgraded version of WP Toolkit Deluxe bundle, combining all previous Deluxe features with Vulnerability Protection (and with more features to be included in the future). 
	* WP Guardian (cPanel addon) only includes Vulnerability Protection, as all other features are already available in WP Toolkit on cPanel by default.
	* The technical name of this feature is virtual patching, and it's powered by Patchstack. Protection rules (also known as virtual patches) are released for high-to-medium-risk vulnerabilities present in Patchstack vulnerability database
* [+] CVSS rating used for ranking and sorting vulnerabilities was replaced with Risk rank
	* Risk rank is an aggregate rating of vulnerability impact based on CVSS rating, EPSS rating, Patchstack Patch Priority and other factors
	* Vulnerability filtering feature was changed from specifying a CVSS score threshold to a simple knob for ignoring low-risk vulnerabilities
	* Low-risk vulnerabilities are now ignored by default on all websites after the upgrade to WP Toolkit v6.4
* [+] Added the ability to change the destination of "Hire a developer" link or hide it completely in global WP Toolkit Settings
* [+] (cPanel) Server administrators can now automatically provision WordPress and sets for user accounts
	* New autoprovisioning options were added to Packages interface as a Package Extension
	* A separate option allows admin to automatically install the latest version of WordPress when a new user account is created
	* A set of plugins & themes can also be selected for automatic installation. 
	* Note: selected set will be installed every time when WordPress itself is installed.
* [+] Must-use plugins are now correctly displayed in the list of plugins with corresponding tags
* [-] WP Toolkit no longer stops working with `Initial data load error: some required fields are not provided` error in some rare cases. (EXTWPTOOLK-11652)
* [-] Certain WP Toolkit processes no longer hang indefinitely if they cannot be finished for some reason. (EXTWPTOOLK-10647)


# 6.3.2 (18 Apr 2024)

* [-] Cloning of sites on CloudLinux OS should no longer fail with "Security of selected WordPress websites cannot be improved" error. (EXTWPTOOLK-10439)
* [-] (cPanel) Mitigating vulnerabilities on the Security screen now works correctly again. (EXTWPTOOLK-11635)

# 6.3.1 (29 Mar 2024)

* [*] Internal improvements
* [-] (Plesk) Links to Plesk in vulnerability notifications now work properly. (EXTWPTOOLK-11550)

# 6.3.0 (27 Mar 2024)

* [+] Added integration with [Wordfence](https://www.wordfence.com/) vulnerability database:
	* WP Toolkit now displays combined information from Patchstack and Wordfence vulnerability databases, with links to both services
	* Some vulnerability entries might happen to be duplicates, but we're working on merging them as well
* [+] Introducing new vulnerability management UI based on [WP Guardian](https://wpguardian.io/)
* [+] Added the ability to filter out vulnerabilities based on their CVSS score to reduce alert fatigue
* [+] (Plesk) Full-featured integration of WP Toolkit into Plesk Dynamic list is now available:
	* Most WP Toolkit features are now accessible directly from Dynamic list in Plesk without having to visit the separate WP Toolkit interface
	* Mass management operations are not in scope of this integration, please use the separate WP Toolkit interface for them
	* To enable this feature, add `appModeFeature = on` under the `[ext-wp-toolkit]` section of the `panel.ini` file
* [+] Added a link to Codeable platform for site admins:
	* Codeable provides access to WordPress experts and developers for WordPress site administrators
	* Unlike many freelancers, Codeable experts and developers will never recommend against the current host
	* To hide the link to Codeable, add `codeableIntegrationFeature = off` under the corresponding section of the `panel.ini` (Plesk) or `config.ini` (cPanel) file.
	* To put your company's name on the Codeable landing page, add `codeableUrlCustomer = your company name` under the corresponding section of the `panel.ini` (Plesk) or `config.ini` (cPanel) file.
* [+] Added API for managing WordPress backups
* [+] Added API for managing Sets
* [+] Backup file name and timestamp are now added to the corresponding `meta.json` file
* [+] Backup API now allows to add an arbitrary description to the corresponding `meta.json` file
* [+] (cPanel) WP Toolkit now works on Ubuntu 22.04
* [*] Security improvements
* [*] Minor assorted improvements to Maintenance Mode
* [*] Improved WordPress installation speed on CloudLinux OS
* [*] Reduced memory consumption when working with vulnerabilities
* [*] (cPanel) Improved WP Toolkit performance via opcache shenanigans
* [*] (cPanel) Improved WP Toolkit responsiveness in case of cPanel user account modifications
* [-] Fixed a bunch of PHP errors and notices appearing in server-level log files
* [-] WP Toolkit now honestly reports if a site could not be added after the scan due to improper directory ownership. (EXTWPTOOLK-9679)
* [-] Scan info message now provides info about reattaching a previously detached site. (EXTWPTOOLK-10109)
* [-] Autoupdate policies are now properly applied to plugins and themes installed via set. (EXTWPTOOLK-10699)
* [-] `Mitigate` action is no longer displayed for vulnerabilities that cannot be addressed by security measures. In fact, since the interface was reworked, this action does not appear at all because it was renamed to `Apply security measure`. (EXTWPTOOLK-11390)
* [-] Scheduled task execution no longer overlaps on servers with thousands of sites. (EXTWPTOOLK-11017)
* [-] Maintenance mode timer is now limited to a maximum of 99 days because come on, really!? (EXTWPTOOLK-11181)
* [-] (cPanel) Smart PHP Update is no longer unable to find the right PHP version on the server. (EXTWPTOOLK-10701)
* [-] (cPanel) Multiple Smart PHP Update processes can now be launched simultaneously. (EXTWPTOOLK-10958)
* [-] (cPanel) Customers can now run scan procedure without getting disappointed by the `Task is not responding, error code 1` error. (EXTWPTOOLK-11184)
* [-] (cPanel) Removed banner in WHM about WP Toolkit Deluxe not being enabled in any packages. (EXTWPTOOLK-10468)

# 6.2.15 (29 Feb 2024)

* [*] Improved the speed and efficiency of installing WordPress updates

# 6.2.14 (24 Jan 2024)

* [*] Internal improvements

# 6.2.13 (07 Dec 2023)

* [-] Autoupdate tasks now have less chances to hang for some mysterious reason. (EXTWPTOOLK-10922)

# 6.2.12 (16 Nov 2023)

* [*] Updated wp-cli to version 2.9 for improved compatibility with WordPress 6.4 and newer.

# 6.2.11 (06 Nov 2023)

* [-] (Plesk) Login to WordPress from Dynamic List works correctly again if certain installed WP plugins are incompatible with PHP version used on a domain. (EXTWPTOOLK-10854)

# 6.2.10 (15 Sep 2023)

* [-] Plugins with uppercase characters in their slug no longer prevent certain WP Toolkit features from working. (EXTWPTOOLK-10772)

# 6.2.9 (12 Sep 2023)

* [*] Achieved minor increase of the WordPress installation speed
* [*] Improved site list performance in certain cases related to WP Toolkit CLI usage
* [*] (cPanel) WP Toolkit no longer removes its own important data in case of package reinstall
* [*] (WP Guardian) Improved site detection mechanism. (EXTWPTOOLK-10596)
* [-] (cPanel) Fixed problem with inability to install WP Toolkit on AlmaLinux 9 due to SHA1 signature issue. (EXTWPTOOLK-10698)

# 6.2.8 (26 Jul 2023)

* [*] (cPanel) Improved WP Toolkit performance under certain circumstances. (EXTWPTOOLK-10662)
* [-] (cPanel) Smart PHP Update no longer fails due to PHP version mismatch error. (EXTWPTOOLK-10633)

# 6.2.7 (14 Jul 2023)

* [-] (cPanel) Users are no longer prevented from accessing WP Toolkit with `Error: Initial data load error: some required fields are not provided` error under certain circumstances. (EXTWPTOOLK-10645)
* [-] (cPanel) Smart PHP Update no longer fails due to reaching FTP account limits. (EXTWPTOOLK-10634)

# 6.2.6 (07 Jul 2023)

* [-] (Plesk) WordPress backup limits in Service Plans and subscriptions are properly working again. (EXTWPTOOLK-10625)
* [-] (Plesk) Sets are no longer lost in time if their owner has internal user ID changed for whatever reason. (EXTWPTOOLK-10071)

# 6.2.5 (04 Jul 2023)

* [*] Improved performance of debugging toggle.

# 6.2.4 (06 Jun 2023)

* [-] (Plesk) Link to WP Toolkit is now available again for clients, together with `Subscriptions` screen. (EXTWPTOOLK-10567)

# 6.2.3 (05 Jun 2023)

* [*] (Plesk) Improved compatibility with Plesk Obsidian version 18.0.53
* [-] Elementor Pro plugin no longer prevents users from logging in to WordPress site via WP Toolkit. This was fixed on the plugin side, so make sure you are running Elementor Pro v3.12.3 or later. (EXTWPTOOLK-10276)
* [-] WP Toolkit no longer provides false positive vulnerability scan results in some rare cases. (EXTWPTOOLK-10396)

# 6.2.2 (27 Apr 2023)

* [-] (cPanel) It is now possible (again) to install WP Toolkit on AlmaLinux 9 servers. (EXTWPTOOLK-10427)
* [-] (cPanel) It is now possible to perform clean installation of WP Toolkit on Red Hat-based Linux distributions with versions earlier than 9. (EXTWPTOOLK-10422)

# 6.2.1 (13 Apr 2023)

* [-] (Plesk) Login to WordPress from Dynamic List now properly works again. (EXTWPTOOLK-10409)

# 6.2.0 (12 Apr 2023)

* [+] Added new API methods for working with plugins and themes on an installation
* [+] (cPanel) Extended Team Manager feature support
* [+] (cPanel) Added AlmaLinux 9 support
* [+] Added help output for the updated `--clear-cache` CLI command
* [*] Adjusted the logic of displaying warnings about outdated PHP versions to make sure alt-php doesn't incorrectly trigger them anymore
* [*] (Plesk) Updated integration with Dynamic list to accommodate for corresponding changes in Plesk
* [-] WP Toolkit no longer shows `Failed to find set with specified ID` error when installing WordPress under certain rare circumstances. (EXTWPTOOLK-9898)
* [-] Unaccessible free trial offer is no longer displayed for Smart Updates. (EXTWPTOOLK-10312)
* [-] Once mitigated via WP Toolkit, CVE-2022-3590 vulnerability is now always properly shown as mitigated. (EXTWPTOOLK-10298)
* [-] Smart Update no longer reports certain combinations of square brackets as a false positive "broken shortcode" issue. (EXTWPTOOLK-10050)

# 6.1.3 (07 Mar 2023)

* [+] `--clear-cache` CLI command now supports partial (targeted) cache reset.
* [-] WP Toolkit no longer shows `Failed to find set with specified ID` error when installing WordPress under certain rare circumstances. (EXTWPTOOLK-9898)
* [-] Vulnerability warning is no longer displayed for cloned websites with already mitigated vulnerabilities. In addition, email notifications about mitigated vulnerabilities allegedly being active are no longer sent to users. (EXTWPTOOLK-10259)
* [-] (Plesk) Service Plan limit `WordPress websites with Smart Update` now works correctly again, as before. (EXTWPTOOLK-10179)

# 6.1.2 (09 Feb 2023)

* [-] WP Toolkit is sending notifications about found vulnerabilities again. (EXTWPTOOLK-10169)
* [-] (Plesk) Copy Data feature is no longer blocked when there's a remote site connected to WP Toolkit. (EXTWPTOOLK-10212)
* [-] Addressed unruly behavior of security measure switches in the menu that addresses CVE-2022-3590 vulnerability. (EXTWPTOOLK-10157)

# 6.1.1 (27 Jan 2023)

* [+] Users can now mitigate CVE-2022-3590 vulnerability in WordPress core on `WordPress Vulnerabilities` screen.
* [*] Improved performance in certain cases related to Smart PHP Updates
* [-] Smart Update now respects page crawling limits set in the config file. (EXTWPTOOLK-10118)

# 6.1.0 (12 Jan 2023)

* [+] Smart PHP Update premium feature is now available. Users can run Smart PHP Update to check how their website will work on a different version of PHP without affecting the production site. This feature is integrated with Plesk Service Plans. To hide this feature, add `smartPhpUpdateFeature = false` to the corresponding section of the `panel.ini` (Plesk) or `config.ini` (cPanel) file.
* [+] (Plesk) WP Toolkit Deluxe offer is now available and can be accessed via Plesk Extension Catalog. It currently includes both Smart Updates and Smart PHP Updates. We will continue adding other premium features to this offer in the future.
* [+] (cPanel) WP Toolkit now supports Team Manager feature.
* [*] Removed all limits on the number of custom labels you can use.
* [*] Renamed product to WP Toolkit.
* [*] (cPanel) Improved performance in cases related to creating addon domains and subdomains.
* [-] Link to PHP version details is no longer lost and is back to its rightful place. (EXTWPTOOLK-9955)
* [-] Corrected the descriptions for several security measures. (EXTWPTOOLK-10012)
* [-] Wordfence plugin no longer breaks cloned WordPress installations. (EXTWPTOOLK-9853)

# 6.0.1 (23 Nov 2022)

* [*] Updated hints about limitations of non-private labels
* [-] `Forced` autoupdate policies are now correctly applied again. (EXTWPTOOLK-9917)
* [-] (Plesk) Smart Updates purchase link is no longer leading to a non-existent page. (EXTWPTOOLK-9914)

# 6.0.0 (17 Nov 2022)

* [+] WP Toolkit now provides REST API for the majority of its features. To learn more about REST API, find the corresponding option in the `Global Settings` on cPanel, or in the `Tools & Settings` > `Remote API` on Plesk.
* [+] Website labels can now be customized:
	* All labels now require users to input a label text. Time to get creative!
	* Labels can have different colors (chosen from a predefined palette)
	* Labels can be private (visible only to the person who adds the label) or non-private (visible to and manageable by everyone who can access the site in WPT)
	* Several private labels (up to five) can be added to a single WP site at once 
    * Only one non-private label per site can be added
	* Existing labels were converted to non-private labels with the same text (their color is a bit different, though)
    * List filters for old labels were removed since there are no predefined labels anymore. Filters for new custom labels will be added in the later releases    
* [+] Server administrators can turn off email notifications sent by WordPress to site administrators after the initial WordPress installation. This can be done in `Global Settings` for the whole server.
* [+] `wp-cli` utility was updated to version 2.7.
* [+] (Plesk) WP Toolkit now supports AlmaLinux 9 & RHEL 9 on Plesk.
* [*] utf8mb4 symbols are now processed correctly for legacy database servers.
* [-] Fixed misprint in the Smart Updates promo text (because we could, not because anyone cared). (EXTWPTOOLK-9742)
* [-] Certain badly coded plugins can no longer break WP Toolkit with `TypeError` error after certain operations. (EXTWPTOOLK-9681)
* [-] File Editor link now works properly in the Maintenance Mode customization dialog. (EXTWPTOOLK-9619)
* [-] Confusing error messages no longer should appear in the log files (depends on whether you are literate or not, though). (EXTWPTOOLK-9605)
* [-] Database no longer becomes corrupted under certain (admittedly rare) circumstances after cloning or copying data. (EXTWPTOOLK-9604)
* [-] Cloned site created by Smart Update is now properly deleted if Smart Update fails. (EXTWPTOOLK-9354 / EXTWPTOOLK-9505)
* [-] WP Toolkit now better detects whether a plugin update was actually installed without errors in case of certain stubborn plugins. (EXTWPTOOLK-9193)
* [-] (cPanel) WP Toolkit now works properly with Spanish language on WHM / cPanel. (EXTWPTOOLK-9856)
* [-] (Plesk) Corrected security status message shown under certain rare circumstances. (EXTWPTOOLK-9638)
* [-] (Plesk) Plesk installer no longer fails with exit code 1 when uninstalling WP Toolkit (boo!). (EXTWPTOOLK-9331)
* [-] (Plesk) Dynamic list no longer shows incorrect WordPress installations in "WordPress" tab. (EXTWPTOOLK-9901)

# 5.12.3 (17 Aug 2022)

* [+] Site Kit plugin from Google was added to a number of default sets.
* [+] (cPanel) WordPress Toolkit now supports installation on Rocky Linux.
* [-] Site administrators running their WordPress sites on PHP 8.0 and higher can now log in to WordPress admin from WordPress Toolkit even if certain unruly or buggy plugins are active on these sites. (EXTWPTOOLK-9070)
* [-] (cPanel) It is now possible again to open global `Settings` menu on cPanel v106. (EXTWPTOOLK-9563)

# 5.12.2 (05 Aug 2022)

* [-] WordPress Toolkit no longer takes waaay too much time to load the list of WordPress installations. (EXTWPTOOLK-9580)
* [-] (cPanel) WordPress installations are no longer shown as broken if MultiPHP is disabled for the corresponding cPanel account. (EXTWPTOOLK-9571)

# 5.12.1 (02 Aug 2022)

* [-] WordPress Toolkit no longer breaks down with `InternalServerError` in case of internal database inconsistency. (EXTWPTOOLK-9555)
* [-] WordPress Toolkit now properly works again with customized `wp-config.php` files. (EXTWPTOOLK-9559)

# 5.12.0 (01 Aug 2022)

* [+] Added new optional security measure that disables WordPress XML-RPC (blocks all requests to `xmlrpc.php`).
* [+] (Plesk) Dynamic list now displays WordPress Toolkit icons in the list item headers for all domains with WordPress sites.
* [+] (Plesk) WordPress Toolkit now fully works on ARM64 architecture (currently supported by Ubuntu 20).
* [*] Autoupdate tasks now work much faster if there are quarantined installations on the server.
* [*] (cPanel) WordPress Toolkit no longer affects the font size of all WHM/cPanel page content.
* [-] WordPress Toolkit database inconsistencies no longer break WordPress installations list. (EXTWPTOOLK-9429)
* [-] (Plesk) Clone and Copy Data now properly work on ARM64. (EXTWPTOOLK-9174)
* [-] (Plesk) `Install` button is no longer missing for some users under certain circumstances. (EXTWPTOOLK-9314)
* [-] (Plesk) Wrong WordPress installations are no longer shown on Installations tab when WordPress Toolkit is opened via Search. (EXTWPTOOLK-9403)

# 5.11.3 (28 Jun 2022)

* [*] Updated translations.

# 5.11.2 (08 Jun 2022)

* [-] `Refresh` button now properly refreshes WordPress installation data. (EXTWPTOOLK-9284)
* [-] Site vulnerability check for multiple sites no longer fails with `Cannot read properties of undefined (reading 'isVulnerable')` error under some circumstances. (EXTWPTOOLK-9290)
* [-] Activating a theme from the `Themes` tab in a site card no longer briefly shows two active themes at once. (EXTWPTOOLK-9291)
* [-] Plugins from blocklist can again be deactivated, but not activated. (EXTWPTOOLK-9292)
* [-] Mass update screen now properly shows autoupdate settings for all assets. (EXTWPTOOLK-9294)
* [-] Plugins can again be uploaded into sets. (EXTWPTOOLK-9298)
* [-] Plugin status is now properly refreshed after plugin activation from the global `Plugins` tab. (EXTWPTOOLK-9323)
* [-] (Plesk) Installation screen properly opens again when installation is launched from Plesk domain card. (EXTWPTOOLK-9302)

# 5.11.1 (27 May 2022)

* [-] WordPress Toolkit now properly works in Safari (again). (EXTWPTOOLK-9268)

# 5.11.0 (26 May 2022)

* [+] Smart Updates feature was redesigned to improve the user experience, focusing on hard data instead of screenshots:
	* Detailed per-page information about found issues is now the main focus of user attention
	* Test website is now fully available for manual review until Smart Update is applied or discarded. This allows users to do in-depth validation for all important pages, including those that could not be covered by screenshots (like checkout pages and so on)
	* Smart Update checks up to 100 website pages now (was 30 pages before)
	* Smart Updates now works faster since it doesn't have to do high-quality screenshots anymore (users have access to the actual test website instead)
* [+] (cPanel) WordPress Toolkit now enables monitoring of `cpanel_php_fpm` service after installation or update to version v5.11.
* [*] WordPress Toolkit v5.11.0 update cannot be installed on CentOS 6 or CloudLinux 6. If you are using these OSes, please update them to at least CentOS 7 or CloudLinux 7. 
* [*] (Plesk) Scan procedure was taught to no longer search for WordPress sites in the Recycle Bin (`.trash`) directory.
* [-] Vulnerability menu now correctly displays available updates for vulnerable sites after they were added by the Scan procedure. (EXTWPTOOLK-9146)

# 5.10.2 (14 Apr 2022)

* [*] WordPress plugins and themes will now be properly autoupdated by WordPress Toolkit after the corresponding autoupdate settings are enabled and `Take over wp-cron.php` option is switched on.
* [*] (cPanel) You can turn off the automatic update of `siteurl` and `home` options in WordPress database after cPanel account modification by setting the server-wide `synchronizeSiteUrlDuringAccountModifyHook` option to `false` in the `config.ini` file. This can be useful for WordPress sites installed in a subfolder and configured in a specific way. (EXTWPTOOLK-8975)
* [-] `Twenty Two` theme now properly conforms to autoupdate settings when it's installed during WordPress core update. (EXTWPTOOLK-8831)
* [-] `WordPress Vulnerabilities` screen now displays a hint if WordPress core update is required to update a vulnerable plugin or theme. (EXTWPTOOLK-8538) 
* [-] (cPanel) WordPress Toolkit now properly detects WordPress installations if `public_html` is a symlink to another directory. (EXTWPTOOLK-8563)
* [-] (cPanel) All WordPress Toolkit features should now work correctly for a given WordPress installation if `public_html` is a symlink to another directory. (EXTWPTOOLK-9059)
* [-] (Plesk) Users can delete plugins that were uploaded manually on the global `Plugins` tab on Windows servers. (EXTWPTOOLK-8695)
* [-] (Plesk) Smart Updates now work properly when proxy mode is disabled for nginx. (EXTWPTOOLK-8798)
* [-] (Plesk) WordPress widgets can now be managed on nginx + PHP-FPM when permalinks are used. (EXTWPTOOLK-8839)
* [-] (Plesk) WordPress can now be installed on Windows servers if PHP 8.1 is used. (EXTWPTOOLK-9045)

# 5.10.1 (21 Mar 2022)

* [-] Scan procedure now works correctly when launched by non-administrator users. (EXTWPTOOLK-8997)

# 5.10.0 (17 Mar 2022)

* [+] WordPress Toolkit now also scans inactive plugins and themes for known vulnerabilities.
* [+] Email notifications about found vulnerabilities now include information about vulnerabilities found in inactive plugins and themes.
* [+] Warning about outdated PHP version now includes a link to the PHP management screen.
* [+] (cPanel) Due to changes related to detachment and scanning procedures WordPress Toolkit will execute a one-time server-wide scan after the update to version 5.10.0.
* [-] WordPress Toolkit now uses correct PHP version for additional domain if docroot of this domain contains docroot of another domain. (EXTWPTOOLK-8648)
* [-] Fixed performance issues related to update availability checks on sites with detected vulnerabilities. (EXTWPTOOLK-8720)
* [-] Replaced non-working link in Smart Updates notification email with a working one. (EXTWPTOOLK-8884)
* [-] When users install plugins or themes with known vulnerabilities, a corresponding entry about their vulnerabilities will be added to the action log. (EXTWPTOOLK-8636)
* [-] WordPress v5.9 and higher can be installed on a domain with PHP 8.1. Note: the support for PHP 8.1 was introduced in WordPress itself, not WordPress Toolkit, but if you have contacted our support team about this issue and were given issue ID EXTWPTOOLK-8689, feel free to switch your PHP handler to version 8.1.
* [-] Certain localized WordPress installations can now be properly updated via WordPress Toolkit. (EXTWPTOOLK-8641)
* [-] You can now update your localized WordPress installation to the latest version of WordPress even if it's not available in the current WordPress installation language. (EXTWPTOOLK-8623)
* [-] WordPress Toolkit can now properly detect login URL that was changed by `Perfmatters` plugin. Make sure you have updated the plugin to version 1.8.7 or higher. Special thanks to Perfmatters team for helping with this issue quickly. (EXTWPTOOLK-8565)
* [-] Inactive plugins and themes with known vulnerabilities are now marked as vulnerable in the WordPress Toolkit interface. (EXTWPTOOLK-8493)
* [-] Inactive plugins and themes with known vulnerabilities can now be updated directly on the `WordPress Vulnerabilities` tab. (EXTWPTOOLK-8492)
* [-] Plugin search in the plugin installation dialog now properly works with space characters. (EXTWPTOOLK-8986)
* [-] (cPanel) Smart Updates no longer fails to detect update issues when nginx caching is enabled. (EXTWPTOOLK-8466)
* [-] (cPanel) WordPress Toolkit no longer pointlessly spams cPanel error logs with locale-related errors. (EXTWPTOOLK-8862)

# 5.9.3 (24 Feb 2022)

* [*] (cPanel) WordPress Toolkit v5.10 will be the last major WordPress Toolkit update that supports CloudLinux 6. After that, WordPress Toolkit will no longer receive updates on CloudLinux 6, except critical security fixes. To continue receiving updates with bugfixes and new features, please update your OS.
* [*] Performance of automatic updates and Smart Updates was improved.
* [-] WordPress Toolkit now can uninstall WordPress plugins if `proc_open` or `proc_close` functions are disabled via `disable_functions` in the currently used PHP handler. (EXTWPTOOLK-8756)

# 5.9.2 (10 Feb 2022)

* [+] Detached WordPress sites are no longer re-added through the `Scan` procedure, making their detachment permanent. If you need to add a detached site back for some reason, find and remove the `.wp-toolkit-ignore` file in the site's root folder.
* [+] WordPress Toolkit Deluxe is now enabled by default on all new cPanel installations.
* [-] `Block author scans` and `Enable bot protection` security measures no longer break WordPress sites installed in a subdirectory. (EXTWPTOOLK-8578)

# 5.9.1 (24 Dec 2021)

* [-] Default autoupdate settings for new WordPress installations are now correctly set to expected values again. (EXTWPTOOLK-8620)

# 5.9.0 (23 Dec 2021)

* [+] WordPress Toolkit now sends email notifications upon discovering vulnerable plugins, themes, or WordPress sites. These notifications can be configured in the same place as other similar notifications.
* [+] Autoupdate policies for sites were extended to include automatic updates of vulnerable assets, and automatic disabling of vulnerable plugins.
* [-] Site vulnerability check now correctly identifies and marks assets that remain vulnerable after they were updated. (EXTWPTOOLK-8583)
* [-] Site vulnerability check no longer bothers with inapplicable sites (broken, quarantined, etc). (EXTWPTOOLK-8585)
* [-] Site vulnerability check should now display applicable fix version instead of the earliest one. (EXTWPTOOLK-8559)
* [-] Site vulnerability check (because what else it could be at this point, right?) now properly marks vulnerable assets on the site card after they are installed. (EXTWPTOOLK-8519)
* [-] Maintenance mode settings are no longer reset to default when you resize the maintenance mode settings window. (EXTWPTOOLK-8539)
* [-] Maintenance mode now properly validates large values for timers. (EXTWPTOOLK-3566)
* [-] WordPress Toolkit UI no longer vanishes without warning when user session expires. (EXTWPTOOLK-8580)
* [-] Comments in web server config file about `Block access to sensitive files` security measure are now properly attributed to this measure. (EXTWPTOOLK-8594)
* [-] (cPanel) `Security` window no longer throws an error when you try to open it under certain circumstances. (EXTWPTOOLK-8515)

# 5.8.0 (09 Dec 2021)

* [+] WordPress Toolkit now regularly scans plugins, themes, and WordPress versions for known vulnerabilities using information provided by [Patchstack](https://patchstack.com/) service. Sites with known vulnerabilities are marked in the site list. Detailed information about found vulnerabilities is displayed in a separate tab of the `Security` window for each site.
* [+] WordPress Toolkit now detects modified WordPress login URL automatically, eliminating the need to specify it manually.
* [+] Blocklist feature now works with CLI operations.
* [*] Updates are no longer checked for blocked plugins.
* [*] Manually launched scan procedure now works much faster.
* [*] Improved the cleanliness of Smart Updates: the procedure should not leave empty folders behind anymore.
* [*] Improved the performance of installing and removing WordPress sites on servers with a lot of connected databases.
* [*] Improved the performance of Action Log when working with very large log files.
* [-] Smart Update results page opened via the link in the notification email now works properly. (EXTWPTOOLK-8488)
* [-] Action log records with non-Latin characters are now properly displayed in all known cases. (EXTWPTOOLK-8427)
* [-] Cloning now properly copies `index.php` to a domain with modified vhost template. (EXTWPTOOLK-8244)
* [-] Innocent valid domains on `Hotlink Protection Settings` window are no longer marked as non-valid when an adjacent non-valid domain is removed from the list. (EXTWPTOOLK-8210)
* [-] Password protection now works for directories with ampersand in their name. (EXTWPTOOLK-6496)
* [-] Correct hint text is now shown for autoupdate settings on WordPress installation screen. (EXTWPTOOLK-8367)
* [-] Description of `Turn off pingbacks` security measure was updated to appease the nitpickers from our security team. (EXTWPTOOLK-8249)
* [-] Description of `Block author scans` security measure was also updated to appease the nitpickers from our security team.  (EXTWPTOOLK-8253)
* [-] Changelog links for plugins and themes were returned on the `Plugins` and `Themes` global tabs and `Updates` screen. (EXTWPTOOLK-8339)
* [-] Remote sites connected via plugin can again be properly updated via WordPress Toolkit without unexpected consequences. (EXTWPTOOLK-8235)
* [-] Database table prefix is no longer modified during Copy Data procedure if `Files Only` option was selected. (EXTWPTOOLK-8452)
* [-] `Database name` link no longer leads to a broken screen. (EXTWPTOOLK-8425)
* [-] (cPanel) `Enable bot protection` and `Block author scans` security measures now work with enabled permalinks. (EXTWPTOOLK-8248)
* [-] (cPanel) WordPress Toolkit no longer fails with `Error: Initial data load error: some required fields are not provided` when opened from WHM interface under certain suspicious circumstances. (EXTWPTOOLK-8299)
* [-] (cPanel) Updates are no longer skipped if `Directory Privacy` feature is disabled via Feature Manager. (EXTWPTOOLK-8518)
* [-] (cPanel) WordPress installations located in a path containing a substring of an addon domain can now be properly registered in WordPress Toolkit. (EXTWPTOOLK-8268)
* [-] (Plesk) Autoupdate tasks are now properly processed even if database limit on a subscription is reached. (EXTWPTOOLK-8505)
* [-] (Plesk) `Log Rotation` button was removed from Action Log on Windows because turns out log rotation isn't actually available on Windows. (EXTWPTOOLK-8448)

# 5.7.4 (19 Oct 2021)

* [*] Updated translations.
* [-] (Plesk) Plesk correctly redirects users to WordPress Toolkit after they install WordPress via APS for some weird reason. (EXTWPTOOLK-8263)

# 5.7.3 (14 Oct 2021)

* [-] Forced automatic updates are now properly working even if one of plugins or themes on a site cannot be updated by WordPress Toolkit for some reason. (EXTWPTOOLK-8301)
* [-] (cPanel) Fixed a number of cases where site URL could be changed unexpectedly after `www` prefix was added to it in WordPress admin area. (EXTWPTOOLK-8252)

# 5.7.2 (12 Oct 2021)

* [*] (Plesk) Optimized log rotation configuration
* [-] Cloning and Copy Data now should correctly process certain links generated by Elementor plugin. (EXTWPTOOLK-5896)
* [-] Cloning now should properly process links generated by WPML plugin. (EXTWPTOOLK-2413)
* [-] Screenshots of the clone used by Smart Updates are now properly removed if Smart Update check fails. (EXTWPTOOLK-8214)
* [-] (cPanel) Scanning no longer fails with `Task is not responding, error code '255'` error under certain circumstances. (EXTWPTOOLK-8237)
* [-] (cPanel) Adding `www` prefix to site URL in WordPress admin and then renaming cPanel account that owns this site will no longer remove the prefix. (EXTWPTOOLK-6604)
* [-] (Plesk) Log rotation now properly works if a server uses SELinux. (EXTWPTOOLK-8247)
* [-] (Plesk) WooCommerce plugin can now be properly installed on Windows servers. (EXTWPTOOLK-8023)

# 5.7.1 (06 Oct 2021)

* [-] WordPress Toolkit no longer spams confusing errors in the product log when removing WordPress sites. (EXTWPTOOLK-8242)
* [-] (Plesk) Sites using wildcard domains are no longer considered broken. (EXTWPTOOLK-8251)
* [-] (Plesk) WordPress sites containing invalid characters in the installation data can no longer break WordPress Toolkit UI. (EXTWPTOOLK-8225)

# 5.7.0 (30 Sep 2021)

* [+] WordPress Toolkit now supports configuring automatic updates for individual plugins and themes. This covers the following changes: 
	* Site-wide autoupdate policy now lets to choose between forcing all plugin or theme autoupdates (like before), or allowing every plugin and theme to use their own autoupdate settings
	* When `Defined individually` update policy is selected, site admins can also choose to enable autoupdates by default for all new plugins or themes installed via WordPress Tookit
	* Autoupdates for individual plugins and themes can be toggled on the respective `Plugins` and `Themes` tabs of the site card
	* New `Autoupdate all plugins / themes` switch added to the `Plugins` and `Themes` tabs of the site card allows toggling autoupdates for all plugins or themes on a site at once
* [+] It is now possible to log in to WordPress when the site is in maintenance mode. This behavior can be turned off via `Restrict access to WordPress admin dashboard` option in the Maintenance Mode settings.
* [+] Hotlink protection feature now allows site admins to configure which file extensions should be protected and which domains can be trusted.
* [+] `Sets` and global `Plugins` tabs now fully support the plugin blocklist feature.
* [+] A new email notification about blocklisted plugins disabled by WordPress Toolkit is now available.
* [+] Server admins can use CLI command `--update-login-url-suffix` to change login URL suffix.
* [+] (Plesk) WordPress Toolkit now shows `Install WordPress` link on Websites & Domains site card if there's no WordPress detected. Once a WordPress site is present, the link is changed to `WordPress Toolkit`.
* [*] Updated look'n'feel of several UI components.
* [*] WordPress Toolkit log entries created after updating WordPress Toolkit to v5.7 are accessible only via the `Logs` screen for now. Old log entries created before the update are still accessible in their old place via File Manager. The ability to download logs and access them via File Manager will be re-added in the next WordPress Toolkit update. Sorry for the inconvenience!
* [*] Security improvements.
* [*] Performance improvements (including faster site scanning process).
* [-] It's no longer possible to trick WordPress Toolkit into cloning the site into itself under certain rare circumstances. (EXTWPTOOLK-4357)
* [-] Cloning should no longer affect the clone source if it has `if` clauses in `wp-config.php` file. (EXTWPTOOLK-4213)
* [-] Cloning now works properly if clone target has common docroot with clone source. (EXTWPTOOLK-4673)
* [-] Autoupdate tasks no longer fail when running on IDN domains. (EXTWPTOOLK-8092)
* [-] WordPress sites no longer get stuck in permanent maintenance mode after site admin restores the default maintenance mode template soon after enabling maintenance mode. (EXTWPTOOLK-8047)
* [-] Cloning and data copy procedures now update all URLs and permalinks even if there's more than a thousand of them. (EXTWPTOOLK-8117)
* [-] You can delete WordPress sites that share database with other WordPress sites via the kebab menu. (EXTWPTOOLK-3067)
* [-] (Plesk) `Customize` button on the maintenance mode settings screen now properly directs users to File Manager. (EXTWPTOOLK-7722)
* [-] (Plesk) Smart Updates purchase button now works properly without confusing errors that mention cPanel. (EXTWPTOOLK-7747)

# 5.6.2 (14 Sep 2021)

* [+] (cPanel) WordPress Toolkit Deluxe is now free for all cPanel server owners.
* [*] (cPanel) WordPress Toolkit button was relocated from `Applications` group and now proudly sits first in the `Domains` group.
* [-] Manual updates to minor WordPress versions are now installed properly regardless of WordPress core autoupdate settings. (EXTWPTOOLK-8168)

# 5.6.1 (19 Aug 2021)

* [-] Datetime picker in `Logs` window no longer breaks everything when someone who's using certain non-English interface languages tries to interact with it. (EXTWPTOOLK-8042)

# 5.6.0 (18 Aug 2021)

* [+] Server admin now has access to server-wide plugin blocklist on the global `Settings` screen. Adding plugin slugs to this blocklist will prevent site admins from installing or activating these plugins via WordPress Toolkit. If these plugins are installed through other means, they will be found and deactivated by WordPress Toolkit with extreme prejudice.
* [+] Site admins can verify checksums of WordPress core files if they suspect their site is infected by malware. They can also reinstall WordPress core without affecting site content.
* [+] `wp-cli` utility was updated to version 2.5. All WordPress Toolkit features, including cloning, should now work properly on PHP 8. Due to this change, the minimum PHP version supported by WordPress Toolkit is now PHP 5.6, so websites working on PHP 5.4 and PHP 5.5 cannot be managed by WordPress Toolkit anymore.
* [+] `wp-cli-bundle` is now shipped together with `wp-cli` utility, providing access to many useful commands previously embedded in `wp-cli` itself.
* [+] Cloning and Smart Updates now properly handle popular caching plugins.
* [+] Users can see WordPress Toolkit log entries that happened before and after a filtered log entry by clicking the `Show in context` icon located to the right of the filtered entry.
* [+] You can now delete WordPress sites through CLI using the `--remove` command.
* [+] (cPanel) WordPress Toolkit now supports Ubuntu on cPanel.
* [+] (Plesk) WordPress-based sites in Dynamic List now have a `WordPress` tab with shortcuts to key WordPress Toolkit features.
* [+] (Plesk) WordPress Toolkit now assigns the corresponding database to a site after installation or cloning.
* [*] Update process for multiple items now works significantly faster due to skipping many unnecessary operations, most of which are too embarrassing to mention here.
* [*] Smart Update procedure itself also works a bit faster in a number of cases.
* [*] Smart Update procedure now provides detailed information about which `.htaccess` customizations prevent it from working properly.
* [*] Detection of PHP versions was improved for WordPress installations accessible via several different domains.
* [*] `Hotlink protection` security measure wasn't really a security measure, so it was moved to a separate switch outside of the `Check security` window.
* [*] Error handling and reporting related to PHP 8 was improved.
* [*] (Plesk) Email notifications sent by WordPress Toolkit now include server hostname in message subject for easier identification.
* [*] (Plesk) Domain management link is now named `Manage domain` to be less confusing.
* [-] `Refresh` button in the `Logs` window now properly works in all known cases (and probably in some unknown ones too). (EXTWPTOOLK-7996)
* [-] WordPress Toolkit no longer insidiously puts sites in endless maintenance mode under certain harmless circumstances. (EXTWPTOOLK-7957)
* [-] Smart Update procedure no longer fails with error if it isn't possible to check one of the site pages due to HTTP status code 500 error. (EXTWPTOOLK-7979)
* [-] WordPress Toolkit no longer tries to update WordPress core if autoupdate is set to `minor` and there's no actual update available. (EXTWPTOOLK-7863)
* [-] (Plesk) A long time ago, in a galaxy far, far away, WordPress Toolkit was showing installation IDs instead of installation names in error messages snown when a plugin couldn't be deleted. This no longer happens and we're not sure if it was a conscious stealth fix, or this bug simply died of old age. (EXTWPTOOLK-3573)
* [-] (cPanel) It is now possible to install WordPress Toolkit on a server with Turkish locale (tr_TR). (EXTWPTOOLK-7648)

# 5.5.1 (20 Jul 2021)

* [-] (Plesk) The size of WordPress Toolkit metadata in Plesk backup files was reduced to ensure that these backups can be restored on servers with huge amount of sites. (EXTWPTOOLK-7898)
* [-] Smart Updates no longer fail to analyze the site due to incorrect shortcode detection. (EXTWPTOOLK-5569)
* [-] Copy Data feature no longer copies the state of `Search Engine Indexing` option. (EXTWPTOOLK-7847)
* [-] WordPress Toolkit now properly works with mysqldump 8.0 and MariaDB / MySQL 5.7. (EXTWPTOOLK-7794)

# 5.5.0 (30 Jun 2021)

* [+] WordPress Toolkit now logs every single action it performs.
* [+] Separate Smart Updates details log is now saved in the logs directory. This log is overwritten every time a new Smart Update procedure is launched.
* [+] Special interface for displaying WordPress Toolkit action logs is now accessible via `Logs` button on site cards. The interface includes filtering, real-time updates, and log rotation settings.
* [+] Database table prefix is now displayed on the `Database` tab of a site card.
* [+] Users can now hover their mouse over the website screenshot to see the date and time when it was made. Clicking the circular `Refresh` button in the top right corner will make a new screenshot.
* [+] New CLI command for setting or resetting WordPress administrator password is available: `--site-admin-reset-password`. Setting a new password is possible via environment variable.
* [+] (cPanel) Email notifications can now be managed in UI. Go to global WordPress Toolkit `Settings` and click `Manage email notifications` under the `General Settings` group. 
* [*] On a related note, email notifications are now sent to server administrators by default.
* [*] Reduced the number of unnecessary screenshots made by the screenshotting service. 
* [*] Site list now loads faster, especially if you have multiple sites.
* [*] Collapsed and expanded states of site cards are now saved per-user (technically, it's per-browser, but let's just pretend that's per-user).
* [*] Mass operations on large number of sites now start much faster than before.
* [*] Site card list has undergone selective cosmetic surgery. No major changes, just a bit of loving polish.
* [-] Certain WordPress sites with `DEFINER` clause can now be properly cloned again. (EXTWPTOOLK-7744)
* [-] Errors are now properly displayed on the cloning and data copy screens, if they happen. (EXTWPTOOLK-7597)
* [-] Logs no longer display empty plugin versions under certain circumstances. (EXTWPTOOLK-7532)
* [-] Logs no longer display empty theme versions under certain circumstances (similar problem as above, but we have a separate bug for it, so why not a separate entry, eh) (EXTWPTOOLK-7533)
* [-] WordPress Toolkit no longer states that `All selected items were updated` even when it couldn't update a theme due to licensing issues. (EXTWPTOOLK-7223)
* [-] Cloning to a subdomain with PHP8 no longer fails with `Uncaught TypeError: unserialize(): Argument #1 ($data) must be of type string` error. (EXTWPTOOLK-7374)
* [-] Cloning and data copying no longer _panics_ when processing files with very long filenames or extensions. (EXTWPTOOLK-7745)
* [-] It's now possible to update plugins and themes that have `rc` string in their version. (EXTWPTOOLK-7743)
* [-] WordPress Toolkit no longer drowns in the depths of infinite recursion under certain circumstances that involve parent and child plugins. (EXTWPTOOLK-7519)
* [-] Copy data procedure no longer displays confusing message about not being able to find any matching tables when everything actually went right. (EXTWPTOOLK-7735)
* [-] (cPanel) Temporary files created during cloning and data copying are now properly deleted in all currently known cases. (EXTWPTOOLK-7675)
* [-] (cPanel) WordPress can now be properly installed by WordPress Toolkit on CloudLinux if CageFS was installed after WordPress Toolkit.(EXTWPTOOLK-7548)
* [-] (cPanel) WordPress Toolkit no longer fails to write logs for fresh cPanel accounts that do not yet have a `logs` directory created by the system. (EXTWPTOOLK-7694)
* [-] (Plesk) `Purchase` button no longer leads to `404 Not Found` page. (EXTWPTOOLK-7746)

# 5.4.5 (16 Jun 2021)

* [*] Security improvements.

# 5.4.4 (09 Jun 2021)

* [*] (cPanel) The option to use upsell links generated by WHMCS is now enabled by default. This option should not affect servers not managed by WHMCS, even when it's enabled.
* [-] (cPanel) Multiple instances of `background-tasks` and `scheduled-tasks` services can no longer be started simultaneously on CloudLinux 6 under certain conditions. (EXTWPTOOLK-7713)
* [-] (Plesk) Restoring a Plesk backup no longer fails if it contains a WordPress site broken for reasons unknown to WordPress Toolkit. (EXTWPTOOLK-7699)

# 5.4.3 (01 Jun 2021)

* [+] (cPanel) Hosters with WHMCS can now use upsell links generated by WHMCS. This option can be enabled on the global `Settings` screen.
* [-] (cPanel) WordPress Toolkit installation no longer fails under certain rare circumstances due to issue in the installer script. (EXTWPTOOLK-7623)

# 5.4.2 (19 May 2021)

* [-] (cPanel) Deluxe feature checkbox in `default` feature list no longer suddenly unselects itself after WordPress Toolkit update. (EXTWPTOOLK-7534)
* [-] (cPanel) First ever scan operation on a server no longer fails for no particular reason. (EXTWPTOOLK-7584)
* [-] (Plesk) New file transfer now properly works on Windows 2012 Servers. (EXTWPTOOLK-7547)

# 5.4.1 (29 Apr 2021)

* [-] `Scan` no longer sends WordPress Toolkit into the infinite recursion spiral under certain rare circumstances. (EXTWPTOOLK-7518)
* [-] Icons on certain buttons are now visible again in Safari browser. (EXTWPTOOLK-7510)
* [-] Issues related to lack of HTTP to HTTPS redirection are now properly displayed in the list of SSL/TLS issues in the site card header, if they are found. (EXTWPTOOLK-7478)
* [-] Background task progress is now properly displayed on the `Updates` screen after page reload. (EXTWPTOOLK-7475)
* [-] (cPanel) It is now possible once again to install WordPress Toolkit on RHEL 7. (EXTWPTOOLK-7522)
* [-] (Plesk) Action links for SSL/TLS issues are now leading to correct domains in all cases. (EXTWPTOOLK-7474)

# 5.4.0 (26 Apr 2021)

* [+] WordPress Toolkit now saves a log of important actions it performs on managed websites. Logs are written in plain text and stored on each domain in the following format: `/logs/wpt_action_logs/action_log_#SITE_UUID#.log`
* [+] Cloning backend was fully redesigned for improved security and performance
* [+] Workflow related to wp-cron management was redesigned:
	* The option was renamed to `Take over wp-cron.php` to avoid the classic "enable to disable" confusion
	* It is now possible to explicitly choose if a replacement cronjob should be created or not via `Create a replacement task when takeover is initiated` switch
	* Replacement cronjobs are now way less strict in regards to user modifications. If WordPress Toolkit cannot find its cronjob, it will not try to recreate the cronjob, concluding that it was knowingly modified or removed by user
	* If user has butchered or removed the replacement cronjob by mistake, it can be recreated by switching off and on the corresponding `Create a replacement...` switch
* [+] (cPanel) Email notifications about updates and quarantined sites are now available on cPanel. There's no UI for managing them at the moment (but we're working on that!), so they are disabled by default. If you want to enable them, put the corresponding option in your `config.ini` file and set its value to `true`:
	* `cpanelAdminSuspiciousInstanceNotificationEnabled` - sends a notification about new suspicious instances to server administrator
	* `cpanelResellerSuspiciousInstanceNotificationEnabled` - sends a notification about new suspicious instances to each reseller
	* `cpanelClientSuspiciousInstanceNotificationEnabled` - sends a notification about new suspicious instances to each client
	* `cpanelAdminAutoUpdatesNotificationEnabled` - sends a digest of new available and installed updates (WordPress core, plugins, themes) to server administrator
	* `cpanelResellerAutoUpdatesNotificationEnabled` - sends a digest of new available and installed updates (WordPress core, plugins, themes) to each reseller
	* `cpanelClientAutoUpdatesNotificationEnabled` - sends a digest of new available and installed updates (WordPress core, plugins, themes) to each client
* [+] WordPress Toolkit now displays actual status of SSL/TLS support and certificate on a site card. If any issues are found, WordPress Toolkit provides a suggestion on how to fix them
* [+] Added installation state as a separate column to the CLI site list output
* [+] WordPress Toolkit now supports AlmaLinux OS on both Plesk and cPanel
* [*] Improved pagination on website list
* [*] Progress display in windows was standardized and unified for better experience
* [*] Various warnings and notifications related to problematic PHP versions were improved and made more consistent
* [*] (cPanel) Improved WHM/cPanel integration scheme for improved reliability
* [*] Minimal WordPress version that can be installed via WordPress Toolkit was increased to WP v4.9
* [-] Cloning can now properly handle URLs with encoded forward slash in database tables. (EXTWPTOOLK-6292)
* [-] Cloning no longer fails if WordPress directories do not have proper access permissions. (EXTWPTOOLK-3089)
* [-] WordPress Toolkit no longer confuses users by telling them they have no sites installed when the site list is empty due to applied filters. (EXTWPTOOLK-6155)
* [-] The list of themes is now properly refreshed after a theme is manually uploaded and activated from the global `Themes` tab. (EXTWPTOOLK-4372)
* [-] It is now possible again to use `Log in` functionality in Safari running on iOS devices. (EXTWPTOOLK-6412)
* [-] Thanks to the new ghostbusting algorithm, orphaned tasks left by killed processes or rebooted server no longer haunt users in the interface. (EXTWPTOOLK-6326)
* [-] Default autoupdate options for minor WordPress releases starting with WordPress 5.6 are now set correctly (EXTWPTOOLK-6579)
* [-] (cPanel) WordPress Toolkit log file no longer devours all disk space on a server with a lot of accounts if cPanel account data contains unreadable characters. (EXTWPTOOLK-6224)
* [-] (cPanel) User-modified execution time of wp-cron.php replacement cronjob is no longer overwritten by WordPress Toolkit. (EXTWPTOOLK-6310)
* [-] (cPanel) WordPress Toolkit no longer doubles certain log entries. (EXTWPTOOLK-6436)
* [-] (cPanel) WordPress Toolkit no longer doubles certain log entries. (EXTWPTOOLK-6436)
* [-] (cPanel) Resellers can now upload plugins and themes when they manage customer websites in cPanel interface. (EXTWPTOOLK-6014)
* [-] (Plesk) `WordPress Toolkit auto-updates management` permission in Plesk now works properly again. (EXTWPTOOLK-6039)
* [-] (Plesk) WordPress Toolkit no longer sends email notifications about available updates after automatically installing these updates. Opinions vary on whether this was a user trolling algorithm or a split personality algorithm. (EXTWPTOOLK-6077)

# 5.3.4 (09 Mar 2021)

* [-] (cPanel) CageFS status in WPT database is now properly synchronized with actual CageFS status on the server on a regular basis. (EXTWPTOOLK-6124)

# 5.3.3 (18 Feb 2021)

* [-] Autoupdate task no longer fails with PHP fatal error under certain circumstances. (EXTWPTOOLK-6454)

# 5.3.2 (17 Feb 2021)

* [-] Updates no longer fail to be installed on sites with more than 30 plugins and themes. (EXTWPTOOLK-6445)

# 5.3.1 (17 Feb 2021)

* [-] When copying data between sites, `Remove missing files` and `Replace files modified on target` options are now working correctly again. (EXTWPTOOLK-6426)

# 5.3.0 (15 Feb 2021)

* [+] The `wp-cli` utility was updated to the latest version, so WordPress Toolkit now works on PHP 8. Yay! On the other hand, minimum PHP version supported by WordPress Toolkit is now PHP 5.4, so websites working on PHP 5.2 and PHP 5.3 cannot be managed by WordPress Toolkit anymore. 
* [+] WordPress Toolkit now supports new autoupdate defaults introduced in WordPress 5.6. Autoupdate settings on new WP 5.6 installations are now set to "major and minor updates" by default. Existing WordPress installations updated to version 5.6 will keep their previous autoupdate settings.
* [+] New WordPress 5.6 installations managed by WordPress Toolkit are not using the `WP_AUTO_UPDATE_CORE` constant for configuring autoupdate settings anymore. Existing WordPress installations updated to 5.6 will keep the constant in `wp-config.php` file until autoupdate settings are changed. The only exception to both these cases is complete disabling of all autoupdates, which will still require WordPress Toolkit to add the constant to `wp-config.php`.
* [+] WordPress Toolkit now identifies and visually marks websites using unsupported version of WordPress, outdated (EOLed) version of PHP, or unsupported version of PHP.
* [+] It is now possible to clone websites with defined `DEFINER` clause in the database dump. If you were ever given issue ID EXTWPTOOLK-946 by our support team for tracking purposes, it's time to rejoice.
* [+] (cPanel) Server administrators can configure both cPanel and WHM upsell links for WordPress Toolkit Deluxe on the global `Settings` screen.
* [*] WordPress Toolkit no longer adds `WP_AUTO_UPDATE_CORE` constant to `wp-config.php` file during operations not initiated by the customer (like checks for availability of updates, and so on). This constant will be added only after site admin has explicitly modified WordPress autoupdate settings.
* [*] WordPress Toolkit now tries its best to create site screenshots for quarantined and otherwise unsupported sites.
* [*] (cPanel) Default WHM upsell link for WordPress Toolkit Deluxe was updated to ensure it points to the proper destination.
* [*] (Plesk) Site list loading speed was increased.
* [-] WordPress sites with very long rows in the database can now be properly cloned. (EXTWPTOOLK-939)
* [-] Plugins are now installed with locale matching current WordPress site locale, if possible. (EXTWPTOOLK-5167)
* [-] WordPress Toolkit can now properly work with sites that have filters and closing PHP tags in `wp-config.php`. (EXTWPTOOLK-4104)
* [-] It is now possible to clone sites with large database tables without encountering the `Got packet bigger than 'max_allowed_packet' when dumping table` error. (EXTWPTOOLK-5778)
* [-] It should now be possible to clone sites with huge (>10 GB) database tables without encountering the 504 error when opening the cloning screen. (EXTWPTOOLK-5154)
* [-] The field formerly known as `Login URL` had its name and hint text updated to clarify that you don't need to specify the full URL here, only the suffix. (EXTWPTOOLK-6107)
* [-] It is now possible to copy data from a site if it has files containing spaces in their names. (EXTWPTOOLK-6360)
* [-] (cPanel) WordPress Toolkit no longer fails to open in WHM with `Request to backend API failed with error: Request failed with status code 504` error after multiple broken installations are found on the server. (EXTWPTOOLK-6404)
* [-] (cPanel) Cloning sites on CloudLinux servers no longer occasionally fails with `Your PHP installation appears to be missing the MySQL extension which is required by WordPress` error. (EXTWPTOOLK-6080)
* [-] (cPanel) WordPress Toolkit no longer fails to open in cPanel under certain rare circumstances with `Failed to load WordPress Toolkit options and settings. Failed to parse response from backend, expected valid JSON` error. (EXTWPTOOLK-6372)
* [-] (Plesk) WordPress Toolkit now displays a nicer error message when it cannot install the remote management plugin on a site due to `upload_max_filesize` restrictions on a remote server. (EXTWPTOOLK-6157)
* [-] (Plesk) Maintenance log no longer contains exceptions if there's at least one remote site connected via plugin on the server. (EXTWPTOOLK-6083)
* [-] (Plesk) Advisor measure `Turn on security autoupdates` can now be applied even if certain sites in the list are broken. (EXTWPTOOLK-6208)

# 5.2.4 (23 Dec 2020)

* [+] (cPanel) It is now possible to have separate WordPress Toolkit Deluxe upsell links in WHM and cPanel. You can use Manage2 interface to configure them, or you can modify the `config.ini` file located in `/usr/local/cpanel/3rdparty/wp-toolkit/var/etc/` (if the file is absent, create it by copying `config.ini.sample`). The upsell URL setting for cPanel is `cpanelWptLiteUpsellUrl`, and the same setting for WHM is called `whmWptLiteUpsellUrl`.
* [*] WordPress Toolkit no longer adds `WP_AUTO_UPDATE_CORE` constant to `wp-config.php` file right after scanning process adds a WordPress installation. This constant will be added only after site admin has explicitly modified WordPress autoupdate settings.
* [-] (cPanel) Rebooting CloudLinux 6 server with WordPress Toolkit no longer causes certain system services (`cpanel`, `tuned`, `atd`, and `crond`) to not start. (EXTWPTOOLK-6065)
* [-] (cPanel) WordPress Toolkit no longer stops working with incomprehensible error if sw`-cp-server` service is stopped. The error is now quite comprehensible! (EXTWPTOOLK-5966)
* [-] WordPress Toolkit no longer adds irrelevant comment to `WP_AUTO_UPDATE_CORE` constant if it's added to `wp-config.php` file. (EXTWPTOOLK-6060)
* [-] (Plesk) Notifications about quarantined WordPress sites are no longer sent for suspended or disabled domains. (EXTWPTOOLK-5398)
* [-] (cPanel) Creation of additional domains is no longer being slowed down by WordPress Toolkit. (EXTWPTOOLK-6094)
* [-] Customized login URLs can now be properly opened in case of certain plugins. (EXTWPTOOLK-5555)
* [-] Clicking on a site in the search results from the `Plugins` or `Themes` tab will no longer show a screen saying that you do not have any WordPress sites. (EXTWPTOOLK-6112)
* [-] The message shown on the search result page if no installations matching the search criteria were found is no longer scaring users by saying that they have no WordPress sites yet. (EXTWPTOOLK-6111)
* [-] (cPanel) WordPress installation no longer fails due to incorrect handling of MySQL server profile. (EXTWPTOOLK-6125)

# 5.2.3 (09 Dec 2020)

* [*] Security improvements.

# 5.2.2 (02 Dec 2020)

* [-] (Plesk) `Log In` link on domain overview page in Active List now works properly. (EXTWPTOOLK-6049)

# 5.2.1 (01 Dec 2020)

* [-] Website screenshots no longer have to be regenerated after the update to WPT 5.2. (EXTWPTOOLK-6048)

# 5.2.0 (30 Nov 2020)

* [+] Resellers now have their own plugin and theme sets.
* [+] It is now possible to choose which theme should be activated upon the installation of a set. This functionality is available both in UI and CLI. As a bonus, similar functionality is now also available for plugins in sets.
* [+] Users will now see a visual indication next to `Check Updates` link if there's a Smart Update test run that was completed and is now waiting for user review.
* [+] WordPress Toolkit now fully supports plugins and themes with underscore symbol in their name. Users of `js_composer` plugin, rejoice!
* [+] CentOS 8 support was added.
* [+] CloudLinux 8 support was added.
* [+] Rules added by WordPress Toolkit to web server config files now have short descriptions explaining what they do.
* [+] (cPanel) A simple dashboard that lists all WordPress Toolkit Deluxe accounts was added. This dashboard can be opened from the `Settings` screen.
* [*] WordPress site management interface is now expanded by default after a site is installed or cloned.
* [*] (cPanel) Multiple performance improvements.
* [-] Checkbox for selecting all sites in the list no longer looks always selected if WordPress Toolkit license is not available. (EXTWPTOOLK-5654)
* [-] Ugly placeholder is no longer displayed in place of WordPress site title if the site was installed with empty `Website title` field. Now users will see a better-looking placeholder! (EXTWPTOOLK-5793)
* [-] `Autoupdate settings` screen no longer works in a weird way if there is more than one site in the list. (EXTWPTOOLK-5983)
* [-] Backup task no longer blows up the interface if current disk space quota is not enough to finish the backup. (EXTWPTOOLK-5784)
* [-] Smart Updates had their optimism reduced and no longer provide false negative prognosis under certain circumstances. (EXTWPTOOLK-6024)
* [-] Smart Updates no longer confuse what exactly needs to be updated during mass updates if `Updates` screen was refreshed after item selection. (EXTWPTOOLK-5761)
* [-] Unclear error sometimes shown during a failed installation of a WordPress site finally became a pretty clear error after all. (EXTWPTOOLK-5133)
* [-] (cPanel) WordPress Toolkit now properly uses session locale settings, displaying the interface in the expected language. (EXTWPTOOLK-5818)
* [-] (cPanel) Renaming user account via `Rename prefixed databases and database users` option now properly updates database prefix of WordPress sites installed in subdirectories. (EXTWPTOOLK-5632)
* [-] (cPanel) WordPress Toolkit Deluxe is no longer incorrectly disabled in the default feature list during WordPress Toolkit update, if it was enabled before. (EXTWPTOOLK-5893)
* [-] (cPanel) It is now possible to create a new domain in cPanel with WordPress Toolkit on CloudLinux 7 if there are more than, uhh, 1280 domains on the server. (EXTWPTOOLK-5989)
* [-] (cPanel) Site administrator email is now generated using parent domain name during WordPress installation on a wildcard domain via CLI. (EXTWPTOOLK-5618)
* [-] (cPanel) Server administrators will no longer be annoyed by the `no packages marked for update` email message on a daily basis. (EXTWPTOOLK-6009)
* [-] (cPanel) WordPress Toolkit now can be installed if `tty` is required in `/etc/sudoers` defaults. (EXTWPTOOLK-5876)
* [-] (Plesk) Infinite redirection no longer occurs when opening website if preferred domain was changed after WordPress installation. (EXTWPTOOLK-478)

# 5.1.4 (17 Nov 2020)

* [-] Transfer Tool no longer fails to transfer data to a server with WordPress Toolkit if transferred account's package didn't exist or wasn't included. (EXTWPTOOLK-5960)

# 5.1.3 (16 Nov 2020)

* [-] (cPanel) WordPress Toolkit no longer fails to operate with `Using $this when not in object context` error under certain mysterious circumstances. (EXTWPTOOLK-5958)

# 5.1.2 (13 Nov 2020)

* [-] (cPanel) WordPress Toolkit can now be installed on CloudLinux 6 servers with `redhat-lsb-core` package. (EXTWPTOOLK-5937)
* [-] (cPanel) WordPress Toolkit Deluxe is no longer enabled by default in feature lists on CloudLinux cPanel servers. (EXTWPTOOLK-5938)
* [-] (cPanel) WordPress Toolkit now can properly work with feature lists that have ampersand character in their name. (EXTWPTOOLK-5916)

# 5.1.1 (05 Nov 2020)

* [-] (Plesk) WordPress sites installed via APS no longer experience errors during the update. (EXTWPTOOLK-5903)

# 5.1.0 (28 Oct 2020)

* [+] Product changelog is now accessible through the WordPress Toolkit Settings window.
* [+] (Plesk) Service plans now have the option to limit the number of backups allowed for each WordPress site. 
* [+] (cPanel) Added support for an alternative "Fixed" licensing model.
* [+] (cPanel) Product translations & localization support were added.
* [+] (cPanel) Installation on CloudLinux 6 and 7 is now supported.
* [+] (cPanel) It is now possible to modify database user credentials on the Database tab of a particular WordPress site.
* [+] (cPanel) Security measure `Block directory browsing` was added.
* [*] (cPanel) Site list performance in WHM was improved.
* [*] (cPanel) WordPress Toolkit Deluxe is no longer enabled in the feature lists by default.
* [-] Website autoupdate tasks will no longer be accidentally skipped in certain rare cases. (EXTWPTOOLK-5825)
* [-] Popup window about automatic updates on the installation drawer was visited by Captain Obvious, so it can now be closed by the `X` (Close) button. (EXTWPTOOLK-5783)
* [-] Backup creation date is now shown with a proper timezone. (EXTWPTOOLK-5777)
* [-] Backup creation date is no longer displayed as one month in the past under certain circumstances. (EXTWPTOOLK-5776)
* [-] When `Update Settings` window is closed, `Available Updates` window no longer opens if it wasn't opened before. (EXTWPTOOLK-5673)
* [-] Smart Updates are no longer confused about what to update in certain cases when previous Smart Update run has detected issues, but update was not applied. (EXTWPTOOLK-5129)
* [-] (cPanel) Fixed the error message text displayed when unsupported PHP version is selected. (EXTWPTOOLK-5791)
* [-] (cPanel) Resellers with `Make the account own itself` option no longer see their own sites twice in the site list. (EXTWPTOOLK-5827)
* [-] (cPanel) WordPress Toolkit updates should now be installed automatically, as intended. (EXTWPTOOLK-5815)
* [-] (cPanel) Now you need to click account name instead of domain name to open site owner's cPanel from WHM. (EXTWPTOOLK-5732)
* [-] (cPanel) `Help` link now opens documentation in a separate tab or window. (EXTWPTOOLK-5720)
* [-] (cPanel) All sites registered in WordPress Toolkit no longer magically vanish from WordPress Toolkit if `.wp-toolkit-identifier` is changed for root or reseller. (EXTWPTOOLK-5699)
* [-] (cPanel) Initial server scan no longer fails if cPanel license was not present after WordPress Toolkit installation. (EXTWPTOOLK-5616)
* [-] (Plesk) WordPress sites on a subscription are no longer displayed as broken if access permissions of `wordpress-backups` directory are set to `000`. On a side note, why would somebody do this?! (EXTWPTOOLK-5739)
* [-] (Plesk) Sites connected via remote plugin no longer become broken after debug is enabled. (EXTWPTOOLK-5716)
* [-] (Plesk) Purchase prompts in WordPress Toolkit Lite no longer lead users to 404 Not Found page. (EXTWPTOOLK-5682)
* [-] (Plesk) WordPress Toolkit data should now be properly restored or migrated by Plesk Migrator without the embarassing `Unable to restore Plesk extension 'wp-toolkit' for subscription` error. (EXTWPTOOLK-5142)
* [-] (Plesk) It is now possible to install a manually uploaded plugin or theme if the archive size is more than 12288 kB. (EXTWPTOOLK-5122)
* [-] (Plesk) Login to WordPress as admin now works after migrating WordPress site to Plesk. (EXTWPTOOLK-1581)

# 5.0.2 (14 Oct 2020)

* [-] (cPanel) Added extra troubleshooting info for admin in case WPT installation fails due to customizations in `etc\sudoers`. (EXTWPTOOLK-5760)

# 5.0.1 (13 Oct 2020)

* [-] (cPanel) WPT now correctly identifies which users have access to Deluxe features. (EXTWPTOOLK-5722)
* [-] (cPanel) Automatic updates now work correctly if WPT is working without a license. (EXTWPTOOLK-5681)
* [-] (cPanel) If WPT installation fails with inability to make certain customizations in `etc\sudoers`, workaround instructions will now be displayed. (EXTWPTOOLK-5731)
* [-] (cPanel) WPT no longer fails to open with `Unable to parse received authentication token` message due to customized `etc\sudoers`. (EXTWPTOOLK-5728)

# 5.0.0 (30 Sep 2020)

* [+] Two words: interface update! No need to worry, though, as the new UI for managing WordPress sites is a logical evolution of the old UI based on newer technologies. Site administrators will find themselves in a fresh-yet-familiar interface with increased focus on site updates, better UX, improved performance and responsiveness.
* [+] WordPress Toolkit Lite experience (applicable for owners of Plesk Web Admin edition) has been redesigned to prettify it and make it more uniform across different screens.
* [+] The list of features available in WPT Lite was updated to make it more consistent and logical:
	* Management of Search Engine Indexing is now available for free in WPT Lite
	* Debugging management is now available for free in WPT Lite
	* Password Protection is now available for free in WPT Lite
	* Update settings for individual sites are now available for free in WPT Lite
	* Upload of plugins & themes in the plugins / themes management is now available for free in WPT Lite
	* Mass update operations (including modification of update settings for multiple sites at once) are now available only in the full (paid) version of WPT
* [+] WordPress Toolkit now supports cPanel. Full public availability with all the details will be announced later.
* [*] Starting with version 5.0, WordPress Toolkit requires Plesk Obsidian to work. Existing WordPress Toolkit installations on Plesk Onyx 17.8 will continue to function, but will no longer receive feature updates. Critical security fixes for WordPress Toolkit on Plesk Onyx 17.8 will continue to be delivered until Plesk Onyx 17.8 reaches end-of-life. We strongly recommend updating to Plesk Obsidian for the best Plesk and WordPress Toolkit experience.
* [*] Branding of default maintenance mode template was updated. It now mentions being powered by WordPress Toolkit instead of Plesk.
* [-] Restoration of backup files no longer fails if they contain some files with read-only permissions. (EXTWPTOOLK-5561)
* [-] Websites are no longer getting stuck in maintenance mode under certain mysterious circumstances after being updated. (EXTWPTOOLK-5531)
* [-] Checkboxes are no longer missing on Security and Updates screens on Safari. (EXTWPTOOLK-5396)
* [-] Other checkboxes were not missing on Safari, but they were not aligned properly, so this was fixed as well. (EXTWPTOOLK-5367)
* [-] WordPres Toolkit now properly updates site URL when a WordPress site is hosted on a subdomain and the main domain is renamed. (EXTWPTOOLK-2268)
* [-] Smart Updates no longer compare shortcode values, avoiding certain false positives during the analysis. Shortcode names are still compared. (EXTWPTOOLK-4618)
* [-] Backup / Restore functionality is no longer displayed as available for sites connected via remote management plugin (because it was never actually available, mind you, not because we removed the feature). (EXTWPTOOLK-5446)
* [-] WordPress Toolkit now displays a helpful hint for Firefox users with enabled pop-up blockers trying to log in to WordPress via WPT. Unsurprisingly, the hint is: turn off pop-up blocker on this page if you want to log in to WordPress via WPT. (EXTWPTOOLK-5634)

# 4.10.2 (16 Sep 2020)

* [-] WordPress installations accessible via several domains with the same docroot can now be updated properly. (EXTWPTOOLK-5566)

# 4.10.1 (11 Sep 2020)

* [-] Installation of WordPress sites no longer fails if the total length of database-related parameters (name, user name, password, and prefix) was too long. (EXTWPTOOLK-5552)
* [-] API no longer returns 'Resource with UID not found' error when removing a subscription with WordPress installed via APS catalog. (EXTWPTOOLK-5098)

# 4.10.0 (09 Sep 2020)

* [+] Site administrators can now back up and restore individual WordPress sites using the brand new 'Back Up / Restore' functionality exclusive to WordPress Toolkit. Site backup files are included in subscription backups by default, so site administrators can use Plesk Backup Manager functionality like scheduled backups or backing up to cloud for further processing. Note: this feature isn't available on Plesk 17.8 Onyx for Windows.
* [*] Updated and improved multiple text messages shown in the product.
* [*] Security improvements.
* [-] Updating WordPress to version 5.5.1 does not trigger wp-cli errors anymore. (EXTWPTOOLK-5490)
* [-] Additional user accounts no longer blow up WordPress Toolkit (figuratively speaking), when accessing Plugins or Themes tabs. (EXTWPTOOLK-5219)
* [-] Server administrators now can access default plugin and theme sets on cloned Plesk installations. (EXTWPTOOLK-3132)
* [-] `Change default database table prefix` security measure does not fail anymore if database table has a period in its name. (EXTWPTOOLK-5376)
* [-] WordPress Toolkit no longer fails to remove one of several WordPress sites if another site under the same user account was broken in a quite specific way that we'd better not explain here for brevity's sake. (EXTWPTOOLK-5486)
* [-] `Update Site URL` control now works properly in List view. (EXTWPTOOLK-5037)

# 4.9.2 (25 Aug 2020)

* [-] It is now possible again to change database setting via CLI for existing WordPress sites. (EXTWPTOOLK-5384)

# 4.9.1 (05 Aug 2020)

* [+] WordPress Toolkit version and build number is now displayed on top of the `WordPress Toolkit Settings` screen.
* [+] CLI utility for the Update Site URL feature was added. It can be accessed through the `plesk ext wp-toolkit --update-site-url` command.
* [+] CLI utility for managing various `wp-config.php` settings was added. It can be accessed through the `plesk ext wp-toolkit --wp-config` command.
* [*] Security measure `Block access to potentially sensitive files` now also blocks public access to .ini files. This change is not applied automatically: to enforce it, reapply the measure on required websites.
* [-] Installing a WordPress site via WPT CLI will no longer display unnecessary and overwhelming information in a background task window inside Plesk UI. (EXTWPTOOLK-5217)
* [-] Jetpack plugin is now installed without PHP errors on Plesk for Windows. (EXTWPTOOLK-5259)

# 4.9.0 (23 Jul 2020)

* [+] Server Administrators can now use Service Plans to limit the number of WordPress sites that customers can install and manage in WordPress Toolkit.
* [+] `Global Settings` screen now has the option to define the default database table name prefix for new WordPress installations.
* [-] It's now possible again to log in to WordPress installations after changing the access password in WordPress Toolkit and not refreshing the installation info via `Refresh` button or other means. (EXTWPTOOLK-5156)
* [-] Security measures are no longer applied to detached websites. (EXTWPTOOLK-5107)
* [-] Redundant backslashes in non-English email notifications from bug EXTWPTOOLK-4699 have returned from the dead and were quickly sent back packing. (EXTWPTOOLK-5042)
* [-] Websites can now be properly cloned if their scheduled task created to replace native wp-cron has no description. (EXTWPTOOLK-5033)
* [-] Update version of manually uploaded plugins and themes is now detected correctly. (EXTWPTOOLK-4966)
* [-] WordPress Toolkit working in Lite mode now correctly accepts update settings specified by users in `wp-config.php` file. (EXTWPTOOLK-682)

# 4.8.4 (29 Jun 2020)

* [-] Update of certain plugins & themes will not mark WordPress sites as broken if there were JSON decoding errors. (EXTWPTOOLK-4736)
* [-] Trying to update a commercial plugin or theme that requires a license will not cause JSON decoding errors anymore. (EXTWPTOOLK-5048)
* [-] Password protection can be enabled on websites that have a double quote character in the site title. (EXTWPTOOLK-5086)
* [-] Permalinks no longer can be broken under certain circumstances when plugins or themes are updated. (EXTWPTOOLK-5118)
* [-] Permalinks no longer can be broken under certain circumstances when a theme is activated. (EXTWPTOOLK-5119)

# 4.8.3 (09 Jun 2020)

* [-] IIS web server configs are no longer erroneously applied to all domains in a subscription with shared IIS application pool if at least one of these domains had WordPress installed. (EXTWPTOOLK-5044)

# 4.8.2 (02 Jun 2020)

* [*] Corrected mistakes in English locale.
* [-] Additional fix was added for the issue previously addressed in WPT 4.8.1: Apache rewrite rules are no longer erroneously applied to all domains in a subscription if at least one of these domains had WordPress installed. (EXTWPTOOLK-5017)

# 4.8.1 (01 Jun 2020)

* [-] Under certain circumstances, Apache rewrite rules were not working properly if `Enabled hotlink protection`, `Block author scans`, or `Enable bot protection` security measures were enabled. (EXTWPTOOLK-5009)

# 4.8.0 (29 May 2020)

* [+] Server administrators can now define default WordPress installation language in the global WordPress Toolkit settings.
* [+] CLI command for enabling and disabling Smart Updates on a site was added. Run `plesk ext wp-toolkit --smart-update` to access it.
* [*] Plugins and themes that require a license for automatic update will now cause a proper error message when users try to update them via WordPress Toolkit without a license.
* [-] `Backup / Restore` links now always lead to the corresponding subscription's Backup Manager screen. (EXTWPTOOLK-1582)
* [-] Smart Updates can now update plugins and themes uploaded manually to WordPress Toolkit if their updates were also manually uploaded to WPT. (EXTWPTOOLK-4080)
* [-] WordPress Toolkit buttons are now properly displayed in Action List if Plesk is in restricted mode. (EXTWPTOOLK-4596)
* [-] German translation for multisites was corrected. (EXTWPTOOLK-4627)
* [-] Certain manually uploaded plugins with incorrect plugin slugs no longer display a broken `Changelog` link. (EXTWPTOOLK-4662)
* [-] It is no longer possible to disable native wp-cron on WordPress sites that use disabled or absent PHP handler. (EXTWPTOOLK-4799)

# 4.7.4 (12 May 2020)

* [-] Updated the hint for `Disable wp-cron` feature in accordance to official WordPress documentation.

# 4.7.3 (30 Apr 2020)

* [*] Fine-tuned Jetpack license checks to avoid clogging up the log files.
* [-] Update of WordPress Toolkit extension no longer fails under certain specific conditions with `Value is not allowed. Allowed one numeric value and '*'` error. (EXTWPTOOLK-4798)

# 4.7.2 (29 Apr 2020)

* [*] A bunch of new default WordPress site names was added. Also, some of the gloomier old names were changed to more positive ones for the sake of cheering people up a bit.
* [-] Updated the destination of `Changelog` links on the `Updates` screen. (EXTWPTOOLK-4733)
* [-] It's now possible to properly disable wp-cron.php if scheduled tasks with missing PHP handlers are present on the server. (EXTWPTOOLK-4764)

# 4.7.1 (22 Apr 2020)

* [-] Made nginx caching great again (well, now you can enable and disable it again). (EXTWPTOOLK-4746)

# 4.7.0 (17 Apr 2020)

* [+] WordPress Toolkit now can update paid plugins & themes, if these updates are available in the WordPress admin area. Note that certain plugins and themes do not support automatic updates, but display notifications about update availability anyway. This particulal scenario isn't fully supported yet.
* [+] WordPress administrators now have the option to disable the execution of `wp-cron.php` via default WordPress mechanism. Enabling this option will automatically create a regular scheduled task in Plesk, which means users can manually adjust the frequency of `wp-cron.php` task execution on a per-site basis. This option can also be enabled for all new installations on the server in the WordPress Toolkit `Settings` menu.
* [+] `Updates` window now displays `Changelog` links for plugins and themes.
* [+] It's now possible to filter WordPress sites in the `Installations` list by their labels.
* [*] Reduced the number of screenshot creation timeouts.
* [-] Exterminated redundant backslashes in non-English email notifications. (EXTWPTOOLK-4699)
* [-] Remote WordPress sites connected via plugin can now be properly updated again. (EXTWPTOOLK-4622)
* [-] WordPress Toolkit now works again on Windows 2012 R2, if access to Plesk via port 443 is enabled. (EXTWPTOOLK-4166)
* [-] Creation time of restore points is not updated anymore if data copy or update procedure is carried out without creating a new restore point. (EXTWPTOOLK-4115)
* [-] Updates for manually uploaded plugins and themes will now be visible in the interface if they become available in WordPress admin area. (EXTWPTOOLK-1785)

# 4.6.0 (12 Mar 2020)

* [+] WordPress administrators can now automatically update their website URL in the WordPress database and `wp-config.php` file based on the actual current URL. This procedure is particularly useful after migrating a website from a different location like your local workstation. The `Update Site URL` feature is available in the  "hamburger" (context drop-down menu) on a WordPress site card.
* [+] CLI utility for the Clone feature was added. It can be accessed through the `plesk ext wp-toolkit --clone` command.
* [+] CLI utility for the Data Copy feature was added. It can be accessed through the `plesk ext wp-toolkit --copy-data` command. 
* [-] Remote sites with modified meta tag generators can now be properly connected to WordPress Toolkit, and their WordPress version is now properly detected. (EXTWPTOOLK-4468)
* [-] It is now possible to install WordPress via CLI if the document root path is specified as `/` or `\`. (EXTWPTOOLK-4457)
* [-] WordPress administrators are no longer forced to reapply security measures due to automatic WordPress core updates flagging the site as insecure. (EXTWPTOOLK-4127)
* [-] WordPress Toolkit now works on Internet Explorer 11 because what is dead may never die. (EXTWPTOOLK-4392)
* [-] Smart Updates of WordPress Core no longer fail with the `Exception: Warning: Failed to fetch checksums. Please cleanup files manually` error. (EXTWPTOOLK-4195)
* [-] Interactive elements and text in the headers of the sliding screens are now much more visible even when a customized color scheme is used. (EXTWPTOOLK-3612)
* [-] Additional services added to Plesk by WordPress Toolkit are now shown properly on Plesk Obsidian. (EXTWPTOOLK-3408)
* [-] `Scan` operation is no longer stuck if a website with a root symlink is found. (EXTWPTOOLK-3096)
* [-] Updates check task no longer fails if a domain with a WordPress site was changed from physical hosting to something else. To tell you the truth, it has been working properly for several years, we simply didn't know for sure when exactly this bug was fixed. Well, better late than never! (EXTWPTOOLK-1042)

# 4.5.1 (31 Jan 2019)

* [-] Proper text is now displayed instead of placeholders for filter names on Mass Update and Mass Security screens. (EXTWPTOOLK-4324)
* [-] Trying to retrieve Jetpack plan status on a site with Free Jetpack plan should not return a weird error anymore. (EXTWPTOOLK-4323)
* [-] WordPress can now be correctly installed without triggering the `Unable to download the WordPress package` error caused by a bug in Guzzle client. (EXTWPTOOLK-4326)
* [-] Users will no longer see a scary `500 Exception Permission Denied` server error when switching to a subscription without access to WordPress Toolkit. (EXTWPTOOLK-4165)
* [-] Smart Updates do not repeatedly fail with the same `plugin not found` task error anymore. (EXTWPTOOLK-4176)

# 4.5.0 (27 Jan 2019)

* [+] Users can now mark their sites with one of the predefined labels (for example, `Staging` or `Production`) for easier identification.
* [+] Commercial Jetpack plugin plans can now be purchased in the plugin installation interface by end-customers. To disable this ability on the server, add `jetpackPluginUpgradeEnabled = false` to your `panel.ini` file.
* [-] WordPress Toolkit can now properly clone and Smart Update sites on Linux OSes, if their `wp-config.php` file is set to read-only. (EXTWPTOOLK-4216)
* [-] Database dumps created during cloning are now properly removed if database import failed during the cloning for some reason. (EXTWPTOOLK-4131)
* [-] WordPress Toolkit no longer apologetically displays `[object Object]` message when users are clicking on `Remove` to remove a site without selecting anything. (EXTWPTOOLK-4159)
* [-] Plugin and theme images in the plugin or theme installation dialogs no longer occupy much more space than allowed on Plesk Obsidian in Safari. (EXTWPTOOLK-3992)
* [-] Preview screenshots no longer occupy much more space than allowed on Plesk Obsidian in Safari. (EXTWPTOOLK-3990)
* [-] WordPress Toolkit update no longer fails due to migration package dependencies. (EXTWPTOOLK-3981)
* [-] Site counters are no longer visually glued to filter names on `Updates` and `Security` screens for several sites. (EXTWPTOOLK-3827)
* [-] Fixed several translation issues.

# 4.4.1 (27 Dec 2019)

* [+] Two secret features were added.
* [*] Internal security improvements.
* [-] Set installation tasks happening simultaneously with WordPress Toolkit update to v4.4 no longer cause WordPress Toolkit to be inaccessible by clients. (EXTWPTOOLK-4089)
* [-] WordPress installation directory field does not lose input focus anymore. (EXTWPTOOLK-4043)
* [-] Plugins and themes can now be properly uploaded to certain directories via CLI on Plesk Obsidian. (EXTWPTOOLK-4037)
* [-] Resellers can now uninstall plugins and themes uploaded by server administrators on the `Plugins` or `Themes` tab. (EXTWPTOOLK-4033)
* [-] In a surprise guest appearance, the status of WordPress updates is now properly refreshed in the `Keep WordPress up-to-date` advice of the Advisor extension. (EXTWPTOOLK-4032)
* [-] A various variety of translation issues was fixed. (EXTWPTOOLK-4022)
* [-] Website screenshots are now automatically updated after the installation and activation of a theme from the `Themes` tab. (EXTWPTOOLK-4005)
* [-] Pagination controls in the list of WordPress sites were peacefully relocated from the East of UI to the West of UI to make sure they are no longer blocked by the window with the status of ongoing tasks. (EXTWPTOOLK-3806)
* [-] `Don't show me again` control on the Smart Update free trial pop-up is now working correctly. (EXTWPTOOLK-4147)

# 4.4.0 (05 Dec 2019)

* [+] Server administrators can now install plugin & theme sets on existing websites at any time. This can be done by visiting the `Sets` tab, finding the required set, and clicking on `Install Set` in the corresponding `'...'` dropdown menu.
* [+] WordPress Toolkit `Settings` tab was redesigned and moved to a separate screen opened via `Settings` button located next to the WordPress Toolkit screen title.
* [*] `Plugins`, `Themes`, and `Sets` tabs were rebuilt using Plesk UI Library to make sure we can quickly redesign and update them in the future.
* [*] Pop-up notifications about successful execution of various operations are now automatically hidden 3 seconds after appearing, so they are (hopefully) less annoying.
* [*] Improved various translation strings.
* [-] Quarantined WordPress sites no longer have a chance to prevent installation of plugins or themes from `Plugins` or `Themes` tabs. (EXTWPTOOLK-4023)
* [-] It should be possible (again) to upload plugins and themes from a specified URL via CLI. (EXTWPTOOLK-3988)
* [-] WordPress Toolkit now properly cleans up temporary files on the server when users install plugins or themes. (EXTWPTOOLK-3977)
* [-] Changing the domain name on very busy servers should not lead to WordPress site becoming quarantined due to timeout anymore. (EXTWPTOOLK-3961)
* [-] Changing the domain name now properly changes the corresponding domain name in WordPress configuration files and database. (EXTWPTOOLK-3901)
* [-] WordPress Toolkit no longer generates PHP warnings during certain plugin updates. (EXTWPTOOLK-3938)
* [-] Proper plugin and theme names are now shown on the `Updates` screen instead of slugs. (EXTWPTOOLK-3826)
* [-] Smart Updates now properly work for WordPress sites where `home` is not where `siteurl` is. (EXTWPTOOLK-3784)
* [-] Loading of WordPress site list no longer slows to a crawl in presence of quarantined sites. (EXTWPTOOLK-3853)
* [-] Pagination in lists now correctly shows the current page number on Plesk Obsidian. (EXTWPTOOLK-3772)
* [-] The second and subsequent pages of the WordPress site list are now working properly on Plesk Obsidian. (EXTWPTOOLK-3771)
* [-] `Owner` links on the WordPress site cards now open in the same browser tab instead of a new tab. (EXTWPTOOLK-3362)
* [-] Outdated link to reference page about WordPress debugging was updated. (EXTWPTOOLK-3178)

# 4.3.5 (05 Dec 2019)

* [-] Fixed several translation issues in die deutsche Sprache. (EXTWPTOOLK-3993)

# 4.3.4 (30 Oct 2019)

* [*] Internal security improvements.

# 4.3.3 (25 Oct 2019)

* [-] Daily maintenance script will no longer put garbage messages in `panel.log` on Plesk Onyx 17.5. (EXTWPTOOLK-3773)

# 4.3.2 (24 Oct 2019)

* [+] Smart Updates now use an new algorithm for analyzing plugin shortcodes, which should address most (if not all) false positives.
* [*] Improved support for Move Domains feature in Plesk Obsidian.
* [*] Smart Updates will warn user if a Smart Update procedure failed due to specific .htaccess customizations.
* [*] Smart Updates sitemap analysis was optimized to increase reliability.
* [-] Screenshot previews in the email notifications about Smart Update results are now displayed properly. (EXTWPTOOLK-3161)
* [-] Caching operations were optimized to address performance issues happening in certain cases with Plesk search and WordPress Toolkit site list. (EXTWPTOOLK-3567)
* [-] Smart Updates will now properly work if sitemap of the cloned website differs from the original due to meddling of certain plugins. (EXTWPTOOLK-3611)
* [-] Handling of nginx config files was changed to address the `Unable to reconfigure domain` error happening under certain circumstances. (EXTWPTOOLK-3626)
* [-] `Sort` control now works properly in the `Security Status` window. (EXTWPTOOLK-3609)
* [-] Smart Updates will not process unnecessary locations from XML sitemaps anymore. (EXTWPTOOLK-3610)
* [-] Smart Updates can now work with websites locally accessible only via domain aliases. (EXTWPTOOLK-3613)
* [-] Certain operations under certain conditions were failing with `Event not scheduled` error. Scheduling certain events was certainly improved to handle this. (EXTWPTOOLK-3616)
* [-] Unsolicited jumping of input focus happening in some cases was removed from the `Clone` window. (EXTWPTOOLK-3633)

# 4.3.1 (03 Oct 2019)

* [+] Cloning and Smart Updates now support websites with permalinks working on nginx.  
* [*] WordPress Toolkit now spotlights 1 month free trial for Smart Updates to server administrators.
* [*] WordPress Toolkit link is now displayed on the Dashboard tab of the new Dynamic List in Plesk Obsidian.
* [*] Improved various interface texts.
* [*] WordPress Toolkit now only supports websites that use PHP version at least 5.6 or newer.
* [-] Placeholders like `[at]` used by various plugins no longer trigger false positive alerts during Smart Update procedure. (EXTWPTOOLK-3550)
* [-] Smart Update controls now display proper information about licensing requirements in WordPress Toolkit SE. (EXTWPTOOLK-1462)
* [-] Screenshot separator has been given some growth hormone to make sure it reaches the bottom of the screenshot comparison block at all times. (EXTWPTOOLK-3492)
* [-] Smart Update screenshots were also given growth hormone to make sure they always reach the bottom of the screenshot comparison. (EXTWPTOOLK-3493)
* [-] Smart Update now resets the scroll position between different screens. (EXTWPTOOLK-3475)
* [-] Regular updates won't be accidentally running instead of Smart Updates when Smart Updates are enabled (and expected) on a website. (EXTWPTOOLK-3462)

# 4.3.0 (04 Sep 2019)

* [+] Smart Update feature has been dramatically redesigned, providing full transparency into the analysis process and streamlining overall user experience. Users can now clearly see what is being checked by Smart Updates and what issues are found on which pages. Full analysis summary with update forecast is now also available to users for making an educated decision about the update or for drilling down into issues found by the system.
* [+] Smart Update now analyzes sitemap to determine which pages to check. Users can create a custom sitemap file specifically for Smart Updates to define which pages should be analyzed (up to 30).
* [+] Smart Update will notify users about preexisting issues on the website even if the update process itself went smoothly.
* [+] Smart Update now checks for unexpected PHP errors, warnings, and notices on the website.
* [+] Smart Update now checks for presence of plugin shortcodes, which typically indicates broken plugins.
* [+] WordPress websites using really old PHP versions (5.4 and older) are now marked in the WordPress Toolkit UI, displaying a warning that WordPress Toolkit will soon stop supporting such websites. A prompt to change the PHP version is displayed for convenience, if users have the permission to manage PHP version on their website.
* [*] Smart Update toggle is now available as a separate switch on the website card, making sure the feature is easy to see and access.
* [*] Smart Update now gets VIP treatment from the screenshot making service, being finally able to request as many screenshots as needed. 
* [*] Smart Update now detects the database limits before actually trying to clone the website for analysis.
* [*] Smart Update threshold settings were removed as a part of UX streamlining.
* [*] Updates screen was optimized, displaying current and available versions, and also hiding plugin & theme descriptions.
* [*] Smart Update screen displayed upon following the link in the notification email is now branding-neutral.
* [*] The algorithm of making website screenshots for Smart Updates was improved to better reflect the actual website look in certain cases. Finally, users can see the ~~goddamned cactus~~ succulent from the Twenty Seventeen theme in all its glory!
* [-] Smart Update failure no longer has a slim chance to accidentally remove the database of the source website under certain rare circumstances. (EXTWPTOOLK-3312)
* [-] Regular update is no longer stealthily performed instead of Smart Update if WordPress website has enabled password protection. (EXTWPTOOLK-3410)
* [-] Smart Update no longer returns weird error message mentioning website ID if 500 HTTP code is encountered during the Smart Update procedure. (EXTWPTOOLK-3234)
* [-] Smart Update now properly cleans up after itself if the procedure went awry. (EXTWPTOOLK-3313 and EXTWPTOOLK-3424)
* [-] Repeated opening and closing of the Updates window will no longer slow down the system (why would you do that anyway?). (EXTWPTOOLK-2669)
* [-] Improved handling of quantum entanglement in the code now allows WordPress Toolkit to identify more accurately whether a certain WordPress installation is broken or infected at any given moment of time. (EXTWPTOOLK-3330)
* [-] Screenshots can now be made for websites hosted on a domain without `www.` prefix if this prefix is present in the WordPress database as a part of the site URL. (EXTWPTOOLK-2799)
* [-] Smart Update will provide a clear explanation instead of a weird error when a website cannot be updated via Smart Update due to Maintenance Mode being enabled. (EXTWPTOOLK-3264)
* [-] Smart Update will provide a clear explanation instead of a weird error when a website cannot be updated via Smart Update due to password protection being used. (EXTWPTOOLK-3265)
* [-] Smart Update is now correctly handling the situation when someone tries to enable it on a multisite (spoiler: it doesn't work and it never did). (EXTWPTOOLK-3378)
* [-] WordPress installations that were broken and fixed afterwards can now be updated without errors while they're still detected as broken by WordPress Toolkit. (EXTWPTOOLK-3147)
* [-] If some of the items in a batch update were not updated successfully, WordPress Toolkit will now display a proper message, providing the necessary details. (EXTWPTOOLK-3151)
* [-] Sitemap is now properly cloned and copied with all necessary URL replacements during the corresponding procedure. (EXTWPTOOLK-3425)
* [-] WordPress Toolkit now verifies the MD5 checksum of the WordPress core package after downloading it. (EXTWPTOOLK-3270)
* [-] If the original WordPress installation on Apache only hosting had any URL structure enabled in "Permalink settings" (except "Plain"), the installation clone
now works correctly and its links no longer redirect to the original. (EXTWPTOOLK-3484)

# 4.2.2 (08 Aug 2019)

* [*] Integration with Website Overview in Plesk Obsidian was updated, making sure that users can still access WordPress Toolkit quickly on each website.
* [*] `Tools` block was moved to a separate column on the website card for increased visibility and easier access.
* [-] Smart Updates no longer fails to update websites that have issues with infinite redirects. (EXTWPTOOLK-3328)
* [-] IDNs (international domain names) are now properly displayed on the Smart Update comparison screen. (EXTWPTOOLK-3239)
* [-] Website screenshots no longer disappear for reasons unknown when user is opening the Smart Update comparison screen. (EXTWPTOOLK-3260)
* [-] Update of multiple websites should not fail to start anymore in certain cases. (EXTWPTOOLK-3284) 
* [-] WordPress Toolkit now exhibits more patience when connecting remote websites via plugin, ensuring that websites hosted on slower servers can be properly connected without timeouts. (EXTWPTOOLK-3278)

# 4.2.1 (26 Jul 2019)

* [-] Users should now be able to perform Smart Update on websites that have a lot of pages. (EXTWPTOOLK-3283)

# 4.2.0 (25 Jul 2019)

* [+] Users can now upload plugins and themes straight to their website when they open the plugin or theme installation dialog on the website card. 
* [+] Website card now has a link to the corresponding domain in Plesk for easier navigation.
* [*] Smart Update speed was dramatically improved.
* [*] Screenshot comparison screens shown in Smart Update details were streamlined.
* [*] Updates screen was cleaned up and polished, eliminating various small UX issues.
* [*] Website card view was optimized, making the card a bit more compact.
* [*] WordPress Toolkit was finally shamed into regularly cleaning up `wp-cli` utility cache on a per-site basis. 
* [*] The `File Manager` link on the website card is now more visible and prominent.
* [*] WordPress Toolkit now displays more details about the update process of WordPress core, plugins, and themes. This change also affects the Smart Update process, making it more transparent.
* [*] Sites can now be installed and cloned into non-empty directories (including directories with random `.php` files, mummified remains of ancient WordPress sites, and so on). Users will be warned and asked for confirmation if target directory is not empty.
* [*] The task responsible for checking and running automatic updates (`instances-auto-update.php`) was rescheduled to run between 1 AM and 6 AM randomly on each server to avoid causing power surges in datacenters.
* [-] Smart Updates: E-mail notifications about Smart Updates no longer include periods after HTML links (this could break certain links). (EXTWPTOOLK-1759)
* [-] Smart Updates: When users are launching Smart Update while the Smart Update license is expired, a proper message will be displayed in UI. (EXTWPTOOLK-2796)
* [-] Smart Updates: Confusing error message about needing a valid SSL/TLS certificate was unconfused. (EXTWPTOOLK-2599)
* [-] Smart Updates: The system now properly notifies users when Smart Update skips a website for some reason during mass update operation. (EXTWPTOOLK-2733)
* [-] Smart Updates: `Select Page` dropdown now properly displays full website URL of WordPress websites installed in a subdirectory. (EXTWPTOOLK-3224)
* [-] Smart Updates: `Open in Plesk` link no longer overlaps the `Select Page` dropdown in some cases. (EXTWPTOOLK-3203)
* [-] Remote websites with broken database connection are now correctly marked as broken in UI. (EXTWPTOOLK-2950)
* [-] CLI output for remote WordPress websites was made more consistent with the output shown for local WordPress websites. (EXTWPTOOLK-2921) 
* [-] Clicking `Help` in Plesk will now take users to the right help page. (XTWPTOOLK-3091)
* [-] Checking the security status under certain circumstances cannot destroy `Plugins` and `Themes` tabs in website cards anymore. (EXTWPTOOLK-2867)
* [-] Plugins can be added to sets via CLI without the `TypeError` error. (EXTWPTOOLK-3079) 
* [-] When users were choosing to copy only the new database tables using `Copy Data` functionality, all tables were copied instead if one of the new tables didn't have the table prefix. This despicable behavior was nipped in the bud. (EXTWPTOOLK-3123)
* [-] The URL of WordPress website installed on a wildcard subdomain is now displayed correctly. (EXTWPTOOLK-3086)
* [-] `Scan` functionality no longer can be broken by the potential data inconsistency mess left by WordPress websites installed via APS. (EXTWPTOOLK-3065)
* [-] Users cannot start the update process for a website that's already being updated. (EXTWPTOOLK-3174)
* [-] Text placeholders are no longer displayed when looking for certain things in Plesk Search. (EXTWPTOOLK-3004)
* [-] Updating WordPress to a newer version on remote hosting with PHP 5.3 will now show a proper error prompt about PHP requirements. (EXTWPTOOLK-3190)
* [-] Smart Updates license key should not have issues with automatic renewal anymore. (EXTWPTOOLK-1470)

# 4.1.1 (20 Jun 2019)

* [*] Handling of wp-cli timeouts was improved to avoid putting innocent WordPress sites into quarantine.
* [-] WordPress Toolkit can now connect remote WordPress sites hosted using Bitnami WordPress images from Amazon Marketplace and other cloud marketplaces. (EXTWPTOOLK-3003)
* [-] Successful update of WordPress core from 5.2.1 to 5.2.2 no longer displays an error in WordPress Toolkit UI. (EXTWPTOOLK-3040)
* [-] WordPress Toolkit no longer slows down dramatically when connecting individual remote WordPress sites if their `wp-config.php` has read-only access permission. (EXTWPTOOLK-3007)

# 4.1.0 (30 May 2019)

* [+] You can now connect remote WordPress installations to WordPress Toolkit and manage them without having SSH root access to the remote host. To access this feature, use the `Connect [Beta]` button on the WordPress website list and provide your WordPress administrator credentials. This feature is a part of the overall Remote Management functionality, so it's available only for Server Administrators as a beta feature.
* [+] WordPress websites are now put into quarantine if WordPress Toolkit is not able to properly access certain important files. WordPress Toolkit could not manage such websites previously, since WordPress installation list froze if these websites were encountered. This should also address issues with connecting remote servers with such websites. 
* [*] WordPress Toolkit now provides more information about broken websites to help users identify the website and troubleshoot the problem.
* [*] Remote Management functionality was improved and updated based on the user feedback.
* [*] Clone and Copy Data operations now handle absolute paths in WordPress database. (EXTWPTOOLK-2601)
* [-] Smart Update procedure is now more patient, so it has much less chance to fail because of a timeout. (EXTWPTOOLK-2723)
* [-] Smart Update purchase button is not available to end users anymore. Only server administrators can now purchase or upgrade Smart Update license, as intended. (EXTWPTOOLK-2730) 
* [-] Smart Update procedure steps now communicate better with each other, so issues encountered by one step are now immediately displayed and do not leave the next steps hanging in the dark until the timeout. (EXTWPTOOLK-2734)
* [-] Rollback of security measures that modify `wp-config.php` file won't have a chance of breaking the WordPress website anymore. (EXTWPTOOLK-2824)
* [-] There was a small chance that WordPress website could be accidentally deleted due to inconsistency of WordPress Toolkit database. It would be very painful, so this chance was extinguished. (EXTWPTOOLK-2686)
* [-] Remote Management feature now checks if PHP interpreter on remote server has all required PHP extensions before trying to connect the website. (EXTWPTOOLK-2677)
* [-] Remote Management feature now displays a proper error message if SSH key contents are not valid. (EXTWPTOOLK-2729)
* [-] Customers with multiple subscriptions can now install WordPress on one of them if another subscription does not have the `Database server selection` permission enabled. (EXTWPTOOLK-1940)
* [-] If you were constantly seeing the confusing `Unable to find the task responsible for the currently running update process. Try running the update again.` message when trying to run the updates, you can breathe a sigh of relief now, as we have identified and fixed the root cause of this annoying behavior. (EXTWPTOOLK-2694)
* [-] It's now possible to clone WordPress located in a particular directory to a directory with the same name in a new subdomain. (EXTWPTOOLK-2906)
* [-] Users should no longer see the `Something went wrong` error when trying to select a domain during the cloning. (EXTWPTOOLK-2823)
* [-] WordPress Toolkit no longer tries to activate themes installed through a set. (EXTWPTOOLK-2621)
* [-] Major WordPress autoupdates no longer fail due to timeout. (EXTWPTOOLK-2925)
* [-] Customers won't be seeing the empty `Plugin/theme set` menu during the WordPress installation if the `Allow customers to use sets when they install WordPress` global option is turned off. (EXTWPTOOLK-2692)
* [-] Server Administrators, on the other hand, will be seeing the proper contents of the `Plugin/theme set` menu during the WordPress installation if the `Allow customers to use sets when they install WordPress` global option is turned off. (EXTWPTOOLK-2693)
* [-] Users can now clone WordPress installations located in a subdirectory to the virtual folder root of their subscription. (EXTWPTOOLK-2939)
* [-] WordPress Toolkit no longer shows vague error message when Smart Update task takes too long to execute. (EXTWPTOOLK-2725)

# 4.0.1 (08 May 2019)

* [-] WordPress Toolkit now displays a correct error message when users are trying to install WordPress 5.2 or update their WordPress to version 5.2 on a domain with PHP version older than PHP 5.6. (EXTWPTOOLK-2902)

# 4.0.0 (25 Mar 2019)

* [+] Beta version of Remote Management functionality is now available. Go to the `Servers` tab and add any Linux-based remote server with WordPress sites to manage them from a single place. This functionality will stay free for a limited time during the Beta stage. A notification will be shown in advance regarding the switch from the free Beta stage to the  Release stage that will require a separate license. Your feedback and input regarding this feature would be highly appreciated.
* [+] Smart Update procedure became more transparent, displaying specific steps and their progress. Now at least you'll know which steps are taking so long!
* [+] Database server info was added to the `Database` tab of the WordPress site card.
* [*] Various links created by WordPress Toolkit on `Websites & Domains` screen are now directing users to the new UI. 
* [*] Users can see the physical path of WordPress sites when cloning them or copying data from one site to another. 
* [*] WordPress Toolkit is now much better prepared both physically and mentally for handling users who try to clone their WordPress site to a destination where another WordPress site already exists.
* [-] Removing a subdomain in Plesk will not remove WordPress installation anymore if this subdomain's docroot was pointing to another domain with WordPress installed. This also covers the use of wildcard subdomains. (EXTWPTOOLK-2580)
* [-] WordPress Toolkit now properly notifies users why Smart Update could not be performed in certain cases. (EXTWPTOOLK-2573)
* [-] The description of `Turn off pingbacks` security measure now explains what will happen if pingbacks are turned off (spoiler: they stop working). (EXTWPTOOLK-2563)
* [-] The em dash punctuation mark is now correctly displayed in plugin and theme names. (EXTWPTOOLK-1990)

# 3.6.3 (06 Mar 2019)

* [-] Cloning procedure now works correctly if `proc_close` or `proc_open` PHP functions are disabled. (EXTWPTOOLK-2533)
* [-] WordPress Toolkit now shows a warning before cloning that `mysqlcheck` utility has detected a database error, so cloning might not work correctly. Users who have not read this warning can continue the cloning procedure. (EXTWPTOOLK-2541)
* [-] The last remnants of upsell prompts for Maintenance Mode were eradicated from the old WordPress Toolkit UI. (EXTWPTOOLK-2540)

# 3.6.2 (26 Feb 2019)

* [*] Maintenance mode management is now available free of charge for owners of Plesk Web Admin edition and similar Plesk editions with basic version of WordPress Toolkit.

# 3.6.1 (23 Feb 2019)

* [-] Maintenance mode no longer gets enabled for no apparent reason after the WordPress Toolkit extension update on websites who have a major WordPress update available. This issue has affected users of basic version of WordPress Toolkit (available in Web Admin and similar editions by default) who have previously enabled the maintenance mode on an affected website at least once. (EXTWPTOOLK-2519)
* [-] WordPress Toolkit database inconsistency no longer has a chance of triggering the removal of certain WordPress websites during the update of WordPress Toolkit extension. (EXTWPTOOLK-2520)

# 3.6.0 (21 Feb 2019)

* [+] Cloning UI was redesigned for improved responsiveness and consistency.
* [+] The UI for copying data (a.k.a. syncing) between installations was redesigned, also for improved responsiveness and consistency. As a side-effect, the procedure formerly known as `Sync` was renamed to `Copy Data`, so users should not be confused about what exactly is going on. 
* [+] Users can now clone WordPress sites to arbitrary subdirectories on target domains.
* [*] Improved the reliability of screenshot generation for WordPress installations, Part II.
* [*] WordPress Toolkit no longer leaves various useless entries in the logs.
* [*] Improved the handling of broken plugins and themes, reducing the number of esoteric error and warning messages shown to users.
* [*] `Install` button now has the focus by default on the WordPress installation form, so hitting Enter after opening the form should immediately launch the installation process.
* [*] Improved the performance of WordPress installation list if it has a lot of WordPress installations. 
* [*] Improved WordPress installation list for viewing on mobile devices.
* [-] WordPress Toolkit database no longer becomes inconsistent when a subscription with two or more WordPress installations is removed. (EXTWPTOOLK-2250)
* [-] Smart Update on Windows servers now checks pages other than the main page. (EXTWPTOOLK-2189)
* [-] Resellers can finally access WordPress Toolkit via the corresponding link in the left navigation panel. (EXTWPTOOLK-1472)
* [-] Users who remove all WordPress installations on the last page in the list of installations are no longer forced to look with despair at the empty screen (unless it was the only page in the list, then yeah). (EXTWPTOOLK-1750)
* [-] `Select All Updates` checkbox on the `Updates` screen is no longer confused about what it should select after several updates were already applied. (EXTWPTOOLK-2175)
* [-] Toolbar buttons above the list of WordPress installations no longer lose their titles after users minimize then maximize the left navigation panel. (EXTWPTOOLK-1394)
* [-] Server Administrator can now manage the `Disable unused scripting` security measure for WordPress installations on locked subscriptions not synchronized with a Service Plan. (EXTWPTOOLK-2178)
* [-] `Disable unused scripting languages` security measure can now be properly applied to WordPress installations on subdomains and additional domains. (EXTWPTOOLK-2323)
* [-] The username and email for WordPress administrator are properly updated in realtime during the WordPress installation procedure if you are changing the destination domain and it has a different owner. (EXTWPTOOLK-2396)
* [-] WordPress Toolkit now properly shows the theme screenshot if it is in the .jpg format (theme screenshots are displayed if WordPress is installed on a domain that does not resolve yet). (EXTWPTOOLK-1907)
* [-] Hotlink Protection And Additional Nginx Directives: `Hotlink Protection` security measure no longer overrides the additional nginx directives on a domain. (EXTWPTOOLK-2305) 
* [-] Hotlink Protection And Mixed Case Domains: `Hotlink Protection` security measure now properly works for domains with mixed case names. (EXTWPTOOLK-2337)
* [-] Hotlink Protection And Expire Headers: `Hotlink Protection` security measure no longer disables Expire headers. (EXTWPTOOLK-2321)
* [-] Update tasks should no longer disappear with cryptic `Unable to find the task responsible for the currently running update process` message. (EXTWPTOOLK-2231)
* [-] WordPress Toolkit now properly cleans up its database when a subdomain with WordPress installation is removed in Plesk. (EXTWPTOOLK-2454)
* [-] `Block access to potentially sensitive files` security measure no longer prevents File Sharing feature in Plesk from working. (EXTWPTOOLK-2279)
* [-] Dramatically reduced the number of false positives for `Block access to potentially sensitive files` security measure. (EXTWPTOOLK-2247)
* [-] Clone procedure now correctly detects and properly modifies certain encoded URLs in the WordPress database. (EXTWPTOOLK-1789)
* [-] Cloned WordPress installations should no longer share their cache with the source installation (we know sharing is caring, but not this time). (EXTWPTOOLK-1773)
* [-] If WordPress Toolkit cannot change the database prefix for all tables when applying the `Database table prefix` security measure, it will properly roll back the changes to prevent website from being broken. (EXTWPTOOLK-2347)
* [-] When WordPress is installed in a subdomain, WordPress Toolkit no longer offers to install it in a subdirectory by default if the main domain already has WordPress installed. (EXTWPTOOLK-2252)
* [-] WordPress can now be installed via CLI into a path containing multiple directories. (EXTWPTOOLK-2260)
* [-] The error message displayed when users try to install WordPress on a domain without an available database now looks nicer. (EXTWPTOOLK-2440)
* [-] WordPress Toolkit now works faster when loading the site list with a large number of websites. (EXTWPTOOLK-2422)

# 3.5.6 (11 Feb 2019)

* [*] WordPress Toolkit compatibility with Plesk 17.9 Preview releases was improved.
* [-] The limit on WordPress sites with Smart Update in a Service Plan is now correctly applied to each subscription instead of being shared between all subscriptions on this plan. Decommunization is important, comrades. (EXTWPTOOLK-2429)

# 3.5.5 (10 Jan 2019)

* [*] Improved the reliability of screenshot generation for WordPress instances.

# 3.5.4 (25 Dec 2018)

* [-] Listing WordPress instances via CLI now works even if there are inconsistencies in the WordPress Toolkit database. (EXTWPTOOLK-2275)
* [-] Plugin-related PHP warnings no longer prevent WordPress instances from smooth update to version 5.0 on PHP 7.3. (EXTWPTOOLK-2232)
* [-] WordPress can now be installed for those customers who for some mind-boggling reason have no e-mail address specified in Plesk. (EXTWPTOOLK-2274) 
* [-] WordPress Toolkit can now be updated correctly even if there are inconsistencies in its own database. (EXTWPTOOLK-2251)

# 3.5.3 (12 Dec 2018)

* [-] WordPress Toolkit notifications now display proper information again instead of existential emptiness. (EXTWPTOOLK-2220)
* [-] Certain security measures no longer add incorrect directives to the Apache config file if the target WordPress instance contains a space in its path. (EXTWPTOOLK-2210)
* [-] WordPress Toolkit does not stealthily install WordPress in a subdirectory anymore if the target domain already has an `/index.php` file. (EXTWPTOOLK-2208)
* [-] WordPress installation screen no longer takes an obscene amount of time to load if there are a lot of domains on the server. (EXTWPTOOLK-2196)

# 3.5.2 (05 Dec 2018)

* [-] WordPress Toolkit now works properly when Alt-PHP is used as a PHP handler. (EXTWPTOOLK-2192)

# 3.5.1 (03 Dec 2018)

* [-] WordPress sites running in a shared application pool on Windows servers no longer become broken after certain new security measures are applied. (EXTWPTOOLK-2191)

# 3.5.0 (29 Nov 2018)

* [+] A big bunch of new security measures was added to ramp up the security of WordPress instances. The measures are not applied automatically, so all users are shown a notification in UI that prompts them to check and apply the new measures. It's now possible to: 
	* Enable hotlink protection
	* Disable unused scripting languages
	* Disable file editing in WordPress dashboard
	* Enable bot protection
	* Block access to sensitive and potentially sensitive files
	* Block access to `.htaccess` and `.htpasswd`
	* Block author scans
	* Disable PHP executing in various cache folders
* [+] WordPress installation experience was updated to unify the UI, so there are no "quick" and "custom" options anymore. WordPress Toolkit now always displays the installation form with all data prefilled, which allows users to make an informed choice: confirm the defaults to install WordPress quickly, or take your time and change the options you want.
* [+] All users can now choose domains from any accessible subscription when installing WordPress. In practical terms this means that you can now install WordPress anytime you click WordPress in the left navigation panel, even if you're a reseller or server administrator.
* [+] WordPress Toolkit CLI for installing WordPress instances was updated to include management of automatic update settings. Specifically, the following options were added: `-auto-updates`, `-plugins-auto-updates`, and `-themes-auto-updates`.
* [+] For those who don't want to use Gutenberg yet after WordPress 5.0 is released, we have added a `WordPress Classic` set that includes `Classic Editor` plugin.
* [+] WordPress Toolkit cache can now be cleared with a special CLI command: `plesk ext wp-toolkit --clear-wpt-cache`. This might be useful for handling issues with invalid WordPress Toolkit cache data like corrupted WordPress distributive or broken lists of languages and versions.
* [*] The yellow `Warning` security status was changed to greenish `OK` to avoid scaring innocent users, since it's actually OK to not have every single security measure applied.
* [*] Security measures `Security of wp-content` and `Security of wp-includes` were unnecessarily restrictive, so they were forced to relax their grip somewhat. (EXTWPTOOLK-1102)
* [-] WordPress Toolkit no longer hangs during the execution of routine daily maintenance tasks when it encounters WordPress instances infected by malware or otherwise operationally challenged. (EXTWPTOOLK-1524)
* [-] Error and warning messages do not display IDN domain names in punycode anymore. (EXTWPTOOLK-1769)
* [-] Resellers and Customers without security management and auto-updates management permissions can no longer manage security and automatic updates. (EXTWPTOOLK-2047)
* [-] WordPress instances no longer become invisible after their installation or cloning process has failed at the very end for some weird reason. (EXTWPTOOLK-1844)
* [-] When users were deleting WordPress instances, WordPress Toolkit was displaying an ambiguous confirmation message, insinuating that WordPress instances will be simply removed from the Toolkit (not deleted). The ambiguity of the message was reduced by several degrees of ambiguousness, so users should now have a very clear idea of what will actually happen. (EXTWPTOOLK-2075)
* [-] `Invalid URL was requested` error is no longer displayed when plugins or themes are activated in the dialog opened directly from the subscription screen. (EXTWPTOOLK-2096)
* [-] WordPress Toolkit no longer refreshes the update cache for detached instances. (EXTWPTOOLK-2049)
* [-] If users are trying to set up Admin credentials for a WordPress instance that does not have any Admin users, WordPress Toolkit does not spectacularly fall on its face anymore, displaying proper error message instead. (EXTWPTOOLK-1826)
* [-] The installation process of WordPress instances is not confused about its own success status anymore if it encounters a file owned by root in the installation directory. (EXTWPTOOLK-2091)
* [-] When WordPress Toolkit encounters a file owned by root during the security status check, it will no longer scare users with a message about the inability to apply a security measure. When the Toolkit finds such a file during the application of security measures, it displays a proper error message now. (EXTWPTOOLK-1875)
* [-] Interface translations no longer display HTML entities in places where they're not supposed to be. (EXTWPTOOLK-2073)
* [-] Removal of multiple instances does not fail anymore if one of the removed instances is broken. (EXTWPTOOLK-1771)
* [-] WordPress Toolkit now properly falls back to the `Install WordPress` service plan option if the `Install WordPress with a set` service plan option was previously selected and this set was removed from the server. (EXTWPTOOLK-1931)
* [-] Smart Update does not enthusiastically notify users about successful updates via notification email anymore if Smart Update was in fact not performed correctly. (EXTWPTOOLK-1760)
* [-] Security status checks became too complacent and stopped working on a routine daily basis. This disgusting behavior was addressed, and users will now be duly notified whenever there's a problem with previously applied security measures. (EXTWPTOOLK-1794)
* [-] Update settings are no longer changed for all WordPress instances selected in the instance list when some of these instances are subsequently filtered out on the Updates screen. (EXTWPTOOLK-2101)
* [-] Smart Update notification emails are now security conscious, providing HTTPS links to Plesk instead of HTTP. (EXTWPTOOLK-1758)
* [-] Cloning procedure now displays proper error message when somebody without the `Subdomain management` permission tries to clone their stuff. (EXTWPTOOLK-1866)
* [-] Failed automatic updates are now properly included in the notification digest. (EXTWPTOOLK-1761)
* [-] WordPress Toolkit has improved its defense against WordPress instances with malformed UTF-8 strings in their settings. Such instances will no longer cause WordPress Toolkit to display a blank screen instead of instance list. (EXTWPTOOLK-1935)
* [-] Users of Russian translation can now see when was the last time WordPress Toolkit checked an instance for updates. (EXTWPTOOLK-1821)
* [-] Speaking of text messages related to updates, a proper error message is now displayed whenever there's a problem with a missing update task. (EXTWPTOOLK-1929)
* [-] WordPress instances that store authentication unique keys and salts in a separate file are no longer considered broken by WordPress Toolkit. (EXTWPTOOLK-2111)
* [-] `Set Contents` pop-up on the WordPress installation screen is now censored out when users open it for a selected set and then switch the set to `None`. (EXTWPTOOLK-1984)
* [-] Maintenance mode no longer displays the countdown on a preview screen if the countdown isn't turned on. Internal debates still rage over whether the Toolkit should play The Final Countdown when it's on, but that's a different story. (EXTWPTOOLK-1845)
* [-] Users will now see a proper error message when they are trying to install WordPress in the same directory where important files like `web.config` were left behind by another WordPress installation. (EXTWPTOOLK-2082)
* [-] WordPress Toolkit now helpfully selects critical security measures not yet applied on the instance when the security scan is ran the first time. (EXTWPTOOLK-2002)
* [-] Text visibility on the Maintenance mode screen was improved to reduce the eye strain of the website visitors around the world. (EXTWPTOOLK-2086)
* [-] Certain placeholder messages were properly localized in the old UI. (EXTWPTOOLK-2021)
* [-] WordPress Toolkit no longer updates the `options` database table of detached WordPress instances when their domain name is changed in Plesk. (EXTWPTOOLK-2074)
* [-] Maintenance mode can now be properly configured if it was never enabled before. (EXTWPTOOLK-2087)
* [-] German translation was updated so that all messages display proper data instead of placeholders. (EXTWPTOOLK-1579)
* [-] `Administrator's username` security measure is not displayed anymore for existing multisite instances, where it doesn't work anyway due to circumstances beyond our control. (EXTWPTOOLK-2106)
* [-] Trying to remove plugins or themes in WordPress Toolkit when they were already removed via other means will now display a proper error message instead of a placeholder. (EXTWPTOOLK-1855)
* [-] Set names are finally restricted to 255 characters, so no more War And Peace on your Sets screen, sorry. (EXTWPTOOLK-1697)
* [-] Maintenance mode screen now properly displays default texts instead of `undefined`. (EXTWPTOOLK-2113)
* [-] Security Status screen can no longer be summoned by users without the corresponding security management permission for a particular instance. Such instances will also no longer be visible on the Security Status screen for multiple instances. (EXTWPTOOLK-1560)
* [-] WordPress Toolkit will display a proper message when one user is trying to secure an instance while another user has already deleted it. (EXTWPTOOLK-1515)
* [-] Redundant requests to wordpress.org on the Plugins and Themes management screens were optimized away. (EXTWPTOOLK-1876)
* [-] The `Select All Updates` checkbox on the Update screen is no longer accessible when users review the intermediate results of the Smart Update procedure. (EXTWPTOOLK-1801)
* [-] The dollar sign displayed on the `Sets` tab when you don't have the full version of WordPress Toolkit is no longer clickable. (EXTWPTOOLK-1822)
* [-] WordPress Toolkit now displays somewhat different result messages when users remove or detach several WordPress instances as opposed to a single one. (EXTWPTOOLK-1755)
* [-] Extremely long WordPress site titles no longer venture outside of the WordPress Toolkit UI. (EXTWPTOOLK-1958)

# 3.4.2 (16 October 2018)

* [*] Improved integration with Advisor extension.

# 3.4.1 (13 September 2018)

* [*] The algorithm used for retrieving the list of plugins and themes was optimized to reduce the load on wordpress.org. 

# 3.4.0 (30 August 2018)

* [+] New CLI commands are now available! You can manage your plugin & theme sets, install them, and upload or remove custom plugins and themes -- all through command line.  Run `plesk ext wp-toolkit --help` to learn more about `sets`, `plugins`, and `themes` commands.
* [+] Security-related screens were redesigned to make them more convenient and usable. In particular, users can now apply any selection of security measures to a number of instances.
* [+] It's now possible to roll back several applied security measures on multiple WordPress instances at once (not that we recommend to do it).
* [+] Users can detach or remove multiple WordPress instances from WordPress Toolkit.
* [+] Server administrators using Plesk versions earlier than Plesk Onyx 17.8 will see a gentle reminder that upgrading their Plesk to version 17.8 or later will give them access to a wonderful world of great new WordPress Toolkit features wrapped in a brand new UI.
* [*] Users can now clearly see when a new website screenshot is being made. Spoilers: the screenshot part of an instance card is temporarily greyed out.
* [*] When you clone WordPress instances, `Search Engine Indexing` is now turned off for the clones by default. Server Administrators can change this behavior on the `Global Settings` tab.
* [*] Screenshots for cloned instances are immediately visible right after the cloning (no more playing hide-and-seek).
* [*] When users synchronize data between WordPress instances, `Files And Databases` option is now selected by default, as opposed to `Files Only` option.
* [*] `Updates` screen for a single WordPress instance now has a magical checkbox that selects or clears all items from `WordPress Core`, `Plugins`, and `Themes` groups.
* [-] Users can now install WordPress instances in subfolders and on additional domains or subdomains even if `wp-config.php` file is present in the parent domain or folder. (EXTWPTOOLK-1765)
* [-] As a corollary of the bugfix mentioned above, users can now clone WordPress instances to additional domains or subdomains even if `wp-config.php` file is present on the parent domain. (EXTWPTOOLK-1766)
* [-] It's now possible to install WordPress into an already existing empty folder. (EXTWPTOOLK-1155)
* [-] Uninstall confirmation dialog in the old UI now has proper text instead of internal localization string. (EXTWPTOOLK-1720)
* [-] WordPress Toolkit no longer redirects users to the first page of the instance list after they have closed the security check screen of an instance located on a different page. (EXTWPTOOLK-1737)
* [-] Custom plugins no longer ignore the `Activate after installation` option, especially if it's not selected. (EXTWPTOOLK-1724)
* [-] WordPress instances with broken database connections can now be found by WordPress Toolkit. Hint: if you fix the database connection, you can manage them in the WordPress Toolkit. (EXTWPTOOLK-1754)
* [-] Smart Updates now work with IDN domains. (EXTWPTOOLK-1719)
* [-] Options on `Update Settings` page will not jump around anymore if you change them before checking for updates has been finished. Note: no options were harmed during the fixing of this bug. (EXTWPTOOLK-1681)
* [-] WordPress Toolkit displays proper error message if one of the instances found during the instance scan is broken. (EXTWPTOOLK-1768)
* [-] CLI command responsible for installing WordPress now adequately explains what's wrong with provided administrator username if there's anything wrong with it. (EXTWPTOOLK-1609)
* [-] WordPress Toolkit no longer executes files of WordPress instances on suspended and disabled domains as a part of its scheduled task. (EXTWPTOOLK-1678)
* [-] Custom themes are now properly activated if `Activate after installation` option is enabled. (EXTWPTOOLK-1717)
* [-] Tooltip is now available for the green icons which indicate that there are no updates on the `Updates` screen shown for multiple instances. (EXTWPTOOLK-1680)
* [-] `wp-config.php` is now removed properly when users remove WordPress instances initially installed as APS packages. (EXTWPTOOLK-1677)
* [-] Smart Update now displays proper error message if it cannot work due to SSL-related problems on the website. (EXTWPTOOLK-1594)
* [-] Security checker `Permissions for files and directories` now should display proper error message if it couldn't do what it had to do. (EXTWPTOOLK-1746)
* [-] `Scan` operation does not refuse to continue working anymore when it encounters a broken instance. (EXTWPTOOLK-1631)

# 3.3.1 (25 July 2018)

* [*] Plugins and themes from the selected set are now properly installed during the provisioning of a subscription with automatic installation of WordPress. (EXTWPTOOLK-1664)  

# 3.3.0 (02 July 2018)

* [+] Filters were added to the plugin and theme installation screen, helping users quickly find what they need (hopefully).
* [+] Users can now check for updates, change update settings and apply updates for multiple WordPress instances at once.
* [+] WordPress Toolkit now has CLI for installing WordPress. Run `plesk ext wp-toolkit --help` for more information.
* [*] Mass security screen is no longer annoying users by constantly rechecking instance security status. You can always recheck the security status by clicking `Check Security` on the Mass Security screen. 
* [-] Security checker `Permissions for files and directories` now agrees that permissions stricter than those set by the checker are not in fact insecure. (EXTWPTOOLK-1577)
* [-] `Log In` button on Websites & Domains screen is no longer displayed on Plesk 17.8 and higher if WordPress access credentials are not known. To make this button appear, go to the WordPress instance list in WordPress Toolkit and specify access credentials for the corresponding instance. Sorry for inconvenience! (EXTWPTOOLK-1573)
* [-] Users can once again change passwords of additional WordPress administrator accounts. (EXTWPTOOLK-1568)
* [-] Server administrators now can manage `Caching (nginx)` checkbox on WordPress instances belonging to subscriptions without the `Manage Hosting` permission. (EXTWPTOOLK-1563)
* [-] This one's somewhat long, so grab your reading glasses. If the administrator username specified during WordPress installation started with a permitted character, but also included forbidden characters, the installation would go on as if nothing wrong happened. However, the administrator username was actually changed during the installation and  the user was not informed about this change, which could be surprising to some users. This behavior was fixed, and username validation works properly now. (EXTWPTOOLK-1561)
* [-] WordPress updates no longer turn off Maintenance Mode if it was enabled before the update. (EXTWPTOOLK-1540)
* [-] Search bars for Plugins and Themes are now separated on Plugin/Theme installation screen. (EXTWPTOOLK-1500)

# 3.2.2 (14 Jun 2018)

* [*] The extension can now be installed on Ubuntu 18.04.

# 3.2.1 (31 May 2018)

* [*] Minor internal security improvements.

# 3.2.0 (24 May 2018)

* [+] New GDPR-compliant interface for installing plugins and themes is now available, completely replacing the old Addendio service. It doesn't have filters yet, but (spoiler alert!) we're working on that.
* [+] Users can now check security and apply critical security fixes for multiple WordPress instances at once. The ability to apply non-critical security fixes en masse was late to the party, so it will have to wait for later WordPress Toolkit releases.
* [*] A couple of new default sets with Jetpack plugin were added.
* [*] `Setup` shortcut was added for those who want to quickly fine-tune their nginx caching settings.
* [*] Smart Update service accuracy was improved. Also, confirmation prompts were added because everybody loves them.
* [-] Toggling stuff like Debug or Maintenance Mode on an instance now immediately updates instance list filters. (EXTWPTOOLK-1389)
* [-] Instance filters went through an extensive bootcamp and became much more useful. You can always see the Filter button now with selected filter and filtered instance count, and you have a "Clear filter" button on the bottom of the instance list as well. (EXTWPTOOLK-1390)
* [-] Smart Update action buttons on the `Updates` screen are now always visible after being taught how to float. (EXTWPTOOLK-1496)
* [-] The "link" button now opens the website in a different tab or window, not in the current one. (EXTWPTOOLK-1445)
* [-] Instance screenshots are now removed if the instance itself is removed (sorry for littering). (EXTWPTOOLK-1413)
* [-] Quick Start menu on the Websites & Domains screen is not hideously deformed on wildcard subdomains anymore. (EXTWPTOOLK-1159)
* [-] If instance cloning has failed during Smart Update, the failed clone is now removed to avoid clone wars (and, uh, copyright infringements). (EXTWPTOOLK-1360)
* [-] Caching management is no longer visible for customers who don't have the permission to manage their hosting settings. (EXTWPTOOLK-1504)
* [-] Users can now turn off countdown timer without having to disable Maintenance mode first. (EXTWPTOOLK-1507)
* [-] In a surprising turn of events, nginx caching management is no longer visible if nginx is not installed on the server. (EXTWPTOOLK-1482)
* [-] Several layout issues were eliminated from the Maintenance mode settings screen. (EXTWPTOOLK-1300)
* [-] It's not possible anymore to confuse Smart Updates by unchecking update items in the middle of Smart Update procedure. (EXTWPTOOLK-1460)

# 3.1.0 (19 April 2018)

* [+] Automatic updates for all plugins or themes on a WordPress instance are now available.
* [+] Smart Update comparison screen was dramatically prettified to the point where it makes certain other screens jealous. The screen also provides more data to help users make informed decisions about whether update will be fine or not.
* [+] Multisite instances are now visually marked in the UI.
* [+] WordPress Toolkit now generates database names with random suffixes when installing WordPress to avoid database name clashes under certain circumstances. Server administrators can also change the database name prefix on the `Global Settings` screen.
* [*] It's now possible to remove multiple plugins or themes at once on the corresponding tabs of an instance.
* [*] Minor improvements and bugfixes related to the new WordPress Toolkit UI.
* [-] Plugins installed on an instance will be visible right away without refreshing the page if all other plugins were previously removed from the instance and the page was not refreshed. (EXTWPTOOLK-1426)
* [-] Smart Update can now be properly performed when `wp-config.php` is located in a non-default folder. (EXTWPTOOLK-1418)
* [-] Preview screenshots now have a much harder time using timeouts to avoid being created. (EXTWPTOOLK-1412)
* [-] Smart Update settings can no longer be tricked into giving the impression of being enabled if the Smart Update is not available for the instance. (EXTWPTOOLK-1379)
* [-] `Updates` screen was trained to be more courageous and can now be successfully opened from the list view. (EXTWPTOOLK-1378)
* [-] `wp-toolkit` CLI utility had some grammar classes and now consistenly understands that `1`, `true`, and `on` all mean one thing (Enabled), while `0`, `false`, and `off` all mean precisely the opposite thing (Disabled). (EXTWPTOOLK-1377)
* [-] Plesk session expiration is now checked on most WordPress Toolkit screens, making for a less confusing working experience. (EXTWPTOOLK-1375)
* [-] Plugins and themes can now be successfully removed in Internet Explorer 11. Why would anyone still use that browser remains a mystery, though. (EXTWPTOOLK-1292)
* [-] Security checker `Permissions for files and directories` now agrees that 750 for directories is quite secure. (EXTWPTOOLK-1103)
* [-] Database naming settings are no longer ignored when WordPress is installed automatically upon the provisioning of a Hosting plan. (EXTWPTOOLK-1098)

# 3.0.5 (11 April 2018)

* [*] Minor improvements and bugfixes related to the new WordPress Toolkit UI.

# 3.0.4 (05 April 2018)

* [*] Improved the reliability of creating instance preview screenshots: WordPress instances were taught to politely stand in the queue instead of overcrowding the screenshotting service like barbarians. (EXTWPTOOLK-1401)
* [-] Activating a theme on a WordPress instance no longer shows themes being switched off on other instances in the list when these instances also have Themes tab opened. (EXTWPTOOLK-1398)

# 3.0.3 (29 March 2018)

* [-] Maintenance screen text is now displayed in English instead of Arabic if WordPress admin UI uses languages not available in Plesk localization packs. (EXTWPTOOLK-1382)
* [-] The contents of the `Actions` dropdown (displayed in the WPT toolbar under certain responsive circumstances) no longer offend the aesthetic sensibilities of users. (EXTWPTOOLK-1355)
* [-] WordPress Toolkit now properly indicates that rollback of an instance restore point has been actually finished. (EXTWPTOOLK-1358) 
* [-] `Scan` and `Import` buttons now work properly when you click on them in the `Actions` dropdown. (EXTWPTOOLK-1362)
* [-] Plesk now properly redirects users to the corresponding page when they remove WordPress instances from `My Apps` screen on the `Applications` tab (ProTip: do not go there for managing your WordPress instances). (EXTWPTOOLK-1365)
* [-] User-provided username will no longer be reset when changing the password in the Password Protection UI. (EXTWPTOOLK-1339)
* [-] Users can now change WordPress admin settings when WPT does not yet know the password to the WordPress instance. (EXTWPTOOLK-1383)
* [-] Smart Update limit in hosting plans is not displayed anymore on Plesk Onyx versions prior to 17.8. (EXTWPTOOLK-1391)

# 3.0.2 (19 March 2018)

* [*] Addendio Plus plugin is no longer installed on all new WordPress instances by default. If you want it to be installed by default, go to WPT Global Settings and enable the corresponding checkbox.
* [-] WPT now properly refreshes instance cache data in Plesk Multi Server environment. (EXTWPTOOLK-1356)
* [-] Users can once again install and manage WordPress instances on domains with PHP 5.3, although we strongly recommend to use at least PHP 5.6 for security reasons. (EXTWPTOOLK-1354)
* [-] Reseller subscriptions can now be customized again without any errors about invalid specified limits. (EXTWPTOOLK-1352)
* [-] Users are now able to remove WordPress instances with missing database. (EXTWPTOOLK-1349)

# 3.0.1 (07 March 2018)

* [*] WordPress Toolkit now properly handles the Plesk session expiration, logging users out and directing them to the login screen whenever the session has expired.
* [-] Smart Update option in Service Plans is now always visible when WordPress Toolkit is installed. (EXTWPTOOLK-1343)
* [-] Database tab is no longer completely broken when it's not possible to fetch all the data that's supposed to be displayed there. (EXTWPTOOLK-1345)
* [-] Document root content will no longer be removed during Smart Update if updated WordPress was installed in a subfolder and no WordPress instance was present in the document root. (EXTWPTOOLK-1344)
* [-] WordPress Toolkit will continue to work nonchalantly if it stumbles upon inconsistencies with WordPress instance restore points. (EXTWPTOOLK-1346)
* [-] It is possible once again to sync data between WordPress instances located on different subscriptions. (EXTWPTOOLK-1348)

# 3.0.0 (06 March 2018)

* [+] Completely redesigned, modern and responsive UI and UX for WordPress instance management. The full list of changes is too numerous to mention here, but the basic idea is: the instance list and overview screen were redesigned and merged into one single UI, providing much better user experience and increased performance. Explore the new WordPress Toolkit and let us know what you think! **Important**: this feature is available only in Plesk Onyx 17.8+.
* [+] Updates can now use the Smart Update service on a per-instance basis. Using Deep Learning algorithms and screenshot analysis, Smart Update checks how the WordPress update would go in a test environment before performing it on the production instance. Glory to our AI Overlords! *ahem* Smart Update supports both automatic and manual updates, providing meatbags with ability to compare the screenshots by themselves. This is a Pro feature that needs to be purchased separately. **Important**: this feature is available only in Plesk Onyx 17.8+.
* [+] Users can enable nginx-based caching via the corresponding switch on the instance card. To configure caching options, go to "Apache & nginx Settings" page on Websites & Domains. **Important**: this feature is available only in Plesk Onyx 17.8+.
* [*] Clone procedure now also watches out for URL changes in certain files. (EXTWPTOOLK-1249)
* [-] Clone procedure no longer fails if `DB_CHARSET` is missing in `wp-config.php` file. (EXTWPTOOLK-1243)
* [-] WordPress Toolkit no longer uses https prefix when automatically installing WordPress during the Service Plan provisioning if SSL/TLS is not available in this Service Plan. (EXTWPTOOLK-1238)
* [-] PHP notices are no longer added to log when you get WordPress instance info from CLI. (EXTWPTOOLK-1308)

# 2.5.2 (21 February 2018)

* [+] The upgrade procedure of the WordPress Toolkit extension was persuaded to be more forgiving -- it can now be successfully repeated if it has previously failed for some reason. (EXTWPTOOLK-1268)
* [-] `Disable scripts concatenation for WP admin panel` security checker no longer invalidates IIS site config if WordPress installation path starts with a digit. (EXTWPTOOLK-1264)

# 2.5.1 (12 February 2018)

* [+] Added new security option that disables script concatenation, preventing certain DoS attacks.

# 2.5.0 (26 December 2017)

* [+] Support for custom plugins and themes. Users can install and manage their own plugins and themes in WordPress through WordPress Toolkit. In addition, server administrators can upload their own plugins and themes to the server-level plugin and theme repositories so that other users on the server can see and install these plugins and themes. Server administrators can also add their plugins and themes to sets for further provisioning.
* [+] Users can install WordPress with a predefined set of plugins and themes during custom WordPress installation. If you do not want your users to access your sets for some reason, you can hide this option on the Global Settings tab.
* [-] The UI hint about WordPress sets preinstallation was not displayed for existing Hosting plans, making it kind of useless. The hint is now displayed for all Hosting plans, regaining its intended usefulness. (EXTWPTOOLK-1081)
* [-] WordPress instance will now be removed from the instance list in WPT if the subscription with this WordPress instance is switched from 'hosting' to 'no hosting'. (EXTWPTOOLK-1043)
* [-] WordPress Toolkit now respects personal boundaries of domains and does not use PHP handler of a parent domain when it should be using PHP handler of the domain where the WordPress is installed. (EXTWPTOOLK-1046)
* [-] Plugin and theme sets are now correctly marked in UI as a feature that requires proper WordPress Toolkit license for users of WordPress Toolkit SE. (EXTWPTOOLK-1039)
* [-] Values of `WP_HOME` and `WP_SITEURL` variables in `wp-config.php` were not properly changed during the cloning of WordPress instances. We've made sure the values of these variables will get proper treatment during the cloning and data synchronization from now on. (EXTWPTOOLK-1069) 
* [-] Maintenance mode assets were not loaded in maintenance mode if any page other than the main page was opened in the browser. (EXTWPTOOLK-978)
* [-] WordPress instances not registered in the WordPress Toolkit were ruthlessly overwritten if somebody performed Quick WordPress installation on the affected domain. WordPress Toolkit was convinced to be more considerate, so now it avoids overwriting unregistered WordPress instances during Quick installation, opting to install new WordPress instances in a subfolder nearby instead. (EXTWPTOOLK-1037)
* [-] PHTML notices are no longer added to `debug.log` on WordPress instance updates. This fix does not affect existing WordPress Toolkit instances which have previously modified Maintenance mode templates, unfortunately. (EXTWPTOOLK-972)
* [-] WordPress Toolkit was displaying a message that a set was installed during the provisioning of a subscription even when nothing of the kind actually happened. This enthusiasm was quite confusing, so WordPress Toolkit now displays the message about set installation only when it is actually installed. (EXTWPTOOLK-1038)
* [-] Instance URLs are now displayed correctly in the Toolkit if `WP_SITEURL` or `WP_HOME` constants in `wp-config.php` have values different from actual website URL. (EXTWPTOOLK-1010)
* [-] The plugin or theme info pop-up window was genetically modified to avoid completely blocking the screen when trying to display a very long plugin or theme name. (EXTWPTOOLK-1012)
* [-] When a WordPress instance without a single plugin was put into maintenance mode, refreshing it in the Toolkit interface resulted in the following error: `Invalid field: slug`. You won't see this error anymore, as all unruly slugs were scurried to graze in the more appropriate fields. (EXTWPTOOLK-1000)

# 2.4.2 (05 December 2017)

* [-] WordPress instances could not be secured via WordPress Toolkit on Plesk 17.8 Preview 8. (EXTWPTOOLK-1004)
* [-] It wasn't possible to install WordPress in the same place three times, overwriting previous installations. We believe that persistence should be rewarded, so we have fixed this issue. (EXTWPTOOLK-1013)

# 2.4.1 (21 November 2017)

* [+] The option to turn off rsync usage for synchronization on Linux was added to Global Settings.
* [-] Addendio service was displaying detached WordPress instances in its drop-down menu. (EXTWPTOOLK-899)
* [-] Successful server backup was adding a warning in the log. (EXTWPTOOLK-991)

# 2.4.0 (16 November 2017)

* [+] Users can specify custom administrator login URL on the "Login Settings" page. This complements various WordPress plugins that change the login URL for security reasons.
* [+] Server Administrator can create sets of themes and plugins for preinstallation with WordPress on new subscriptions.
* [+] On Linux, rsync is now used to synchronize files between instances. This improves performance and adds two more sync options: one allows replacing newer files modified on target (enabled by default), another allows removing files from target that were removed from the source.
* [+] Hosting plans have a new option to preinstall WordPress with an optional predefined set of themes and plugins on newly created subscriptions.
* [+] Multiple WordPress Toolkit settings previously available only via editing `panel.ini` file can now be changed by the server administrator on the Global Settings page of WordPress Toolkit.
* [*] WP-CLI utility was updated to version 1.4.
* [-] WordPress Toolkit could not update secret keys in `wp-config.php` if some of the keys were missing. (EXTWPTOOLK-795)
* [-] Mass update procedure was stopped if a single theme or plugin could not be updated. We have convinced the procedure to continue as usual in this case, and display a warning instead. (EXTWPTOOLK-943)
* [-] Broken WordPress instances registered in WPT could not be repaired by performing data sync from a working instance. (EXTWPTOOLK-904)
* [-] WordPress Drop-Ins were displayed on the "Manage Plugins" page as inactive plugins without descriptions. Attempting to activate them from this page resulted in errors. Now Drop-Ins are not displayed in the plugin list. (EXTWPTOOLK-967)
* [-] When securing database for a WordPress instance, `wp_` substring was replaced not only in the beginning, but also in the middle of table names. (EXTWPTOOLK-905)
* [-] Some operations performed by customers were logged as if they were performed by the server administrator. (EXTWPTOOLK-774)
* [-] On Windows servers it was impossible to clone WordPress instances with files that had spaces in their names. (EXTWPTOOLK-785)
* [-] Under certain circumstances, switching languages took up to several minutes. (EXTWPTOOLK-797)
* [-] After removing a domain that had a subdomain with a WordPress instance registered in WordPress Toolkit, the user could still see this instance in WordPress Toolkit. (EXTWPTOOLK-784)
* [-] Setting `skip_name_resolve = on` in the MySQL server configuration resulted in failure to clone instances. (EXTWPTOOLK-806)
* [-] In some cases WordPress Toolkit did not detect and notify users that a website stopped responding after WordPress instance synchronization. (EXTWPTOOLK-778)
* [-] Addendio service sometimes tried to install Addendio PLUS plugin when it was already installed, which resulted in a warning in the `panel.log` file. (EXTWPTOOLK-913)
* [-] When Resellers used system-wide search, they could see WordPress instances that did not belong to them or their customers. (EXTWPTOOLK-917)

# 2.3.1 (12 October 2017)

* [+] [Addendio](https://addendio.com/) service is now used by default for installing plugins and themes. Enjoy flexible filtering and additional plugin / theme catalogs to choose from.
* [+] When users perform custom WordPress installation, WordPress Toolkit now asks users if they want help with installing plugins.
* [-] After the discussion with WordPress Security team, the 'Version information' security check was removed because it wasn't useful and generated issues in certain cases. (EXTWPTOOLK-852)
* [-] After synchronizing instances, the source instance page had information about the target instance. (EXTWPTOOLK-922)

# 2.3.0 (24 August 2017)

* [+] A restoration point can now be created for a WordPress instance before running operations that have a risk of damaging the instance, such as upgrading it or syncing data. After such operation the instance can be rolled back to the restoration point.
* [+] A new security check 'Disable pingbacks' was added. It prevents attackers from exploiting the WordPress Pingback API to send spam and launch DDoS attacks.
* [+] A link to the list of WordPress instances was added to the left navigation pane in Power User view and the Customer Panel.
* [*] A confirmation dialog is now shown before updating multiple WordPress instances.
* [*] A confirmation dialog is now shown before installing a WordPress instance to a database which is already used by another instance.
* [*] A confirmation dialog is now shown if WordPress installation can overwrite certain files, created by some other CMS.
* [*] Now the WordPress Toolkit does not allow synchronizing databases between WordPress instances that share a single database.
* [-] The message about synchronizing an instance with an older WordPress version to an instance with a newer version was corrected. (EXTWPTOOLK-736)
* [-] The string placeholder was used instead of the domain name on the clone page when German language was used in the user interface. (EXTWPTOOLK-771)
* [-] WordPress Toolkit could not work with instances where the `is_admin` function was used in `wp-config.php`. (EXTWPTOOLK-722)
* [-] Changing the Plesk encryption key after a failed attempt to clone a WordPress instance could result in all further attempts failing. (EXTWPTOOLK-657)
* [-] When cloning a WordPress instance, an error on the database migration step, could result in file transfer step marked as failed. (EXTWPTOOLK-701)
* [-] When cloning an instance, the WordPress Toolkit searched for possible locations of `wp-config.php` in a wrong order, which could result in a failure to clone the instance. (EXTWPTOOLK-704)
* [-] A customer having no access to the WordPress toolkit could indeed have an 'Install Wordpress' button, which actually did not perform any action. (EXTWPTOOLK-721)
* [-] The "Administrator's username" security check was displayed in a wrong section of the Secure WordPress dialog. (EXTWPTOOLK-695)
* [-] Cloning or synchronizing WordPress instances could fail due to unquoted escape sequences in file paths. (EXTWPTOOLK-749)

# 2.2.1 (20 July 2017)

* [-] Some parts of the security check screen didn't show proper text in the Special Edition of the WordPress Toolkit if non-English locale was used. (EXTWPTOOLK-699)
* [-] The buttons on the maintenance mode setup screen had no labels and performed no actions if non-English locale was used. (EXTWPTOOLK-700)

# 2.2.0 (19 July 2017)

* [+] The Special Edition of WordPress Toolkit is now available for all users of Plesk Web Admin edition. This version offers the basic features of WordPress Toolkit for free.
* [*] Improved handling and reporting of WordPress upgrade errors.
* [*] The built-in help for command-line utility has been improved and updated.
* [-] The dialog for removing a broken instance had no text. (EXTWPTOOLK-671)
* [-] After detaching an instance, WordPress Toolkit did not properly set the instance's autoupdate settings. (EXTWPTOOLK-653)
* [-] Spaces were missing in the text on the cloning page for some languages. (EXTWPTOOLK-660)
* [-] When user performed a custom WordPress installation and specified `admin` as a WordPress administrator username, this username was replaced on the Securing Instance step of the installation. Now the `admin` username is not replaced if explicitly specified, and the instance is marked as insecure instead. (EXTWPTOOLK-507)
* [-] During the upgrade, the default WordPress maintenance page was used instead of the maintenance page configured in WordPress Toolkit. (EXTWPTOOLK-644)
* [-] Manually removing a database without using Plesk could result in inability to install or clone WordPress instances. (EXTWPTOOLK-471)
* [-] WordPress Toolkit could not work with an instance that had any code requiring `wp-settings.php` in `wp-config.php`. Now WordPress Toolkit ignores such code when working with the instance and provides improved error reporting for `wp-config.php` issues. (EXTWPTOOLK-638)
* [-] If a theme or a plugin failed to update, no error message was shown. Now WordPress Toolkit shows a comprehensive error message in such case. (EXTWPTOOLK-489)
* [-] Some plugins dependent on other plugins (such as WooCommerce Germanized plugin) could not be activated via the WordPress Toolkit. (EXTWPTOOLK-621)
* [-] Repeating previously failed clone procedure for a WordPress instance failed again if the database user was linked to another database. (EXTWPTOOLK-658)
* [-] Removing the database of a cloned website resulted in inability to clone it again to the same domain and with the same database name. (EXTWPTOOLK-669)
* [-] If user was cloning a subdomain-based WordPress multisite when no valid domains were available, WordPress Toolkit displayed an ugly-looking error without even opening the Clone screen. To avoid hurting the aesthetic sensibilities of users, the error is now displayed properly on the Clone screen and is looking quite fabulous. (EXTWPTOOLK-639)
* [-] If cloning of a WordPress installation was blocked by database import or export errors, the WordPress Toolkit reported that the installation was not configured, but did not explain the actual problem. Now it correctly detects and reports the problem that caused the error. (EXTWPTOOLK-636)
* [-] Themes with descriptions containing non-ASCII characters were breaking the functioning of theme search in WordPress Toolkit. (EXTWPTOOLK-579)
* [-] When synchronizing data between two WordPress instances, the maintenance mode page displayed on the target instance tried to use the resources located on the source instance. (EXTWPTOOLK-631)
* [-] Trying to enable maintenance mode on a WordPress instance of version earlier than 4.3 resulted in an error. (EXTWPTOOLK-686)

# 2.1.2 (29 June 2017)

* [-] Repeatedly scanning a subscription for WordPress instances resulted in autoupdate turned off for all found instances. (EXTWPTOOLK-652)

# 2.1.1 (15 June 2017)

* [-] If the subscription was configured to use PHP 5.3 or earlier, WordPress Toolkit erroneously detected subscription's WordPress instances as broken. (EXTWPTOOLK-632)

# 2.1.0 (14 June 2017)

* [+] Users can now protect their WordPress websites with a password. Anyone browsing a password-protected website receives the "401 Unauthorized" response unless they provide the correct login and password.
* [+] Users can now manually put their WordPress websites into maintenance mode. Users are also able to edit the placeholder page that is displayed to those visiting a WordPress website under maintenance.
* [+] The "WordPress register" event can now be used with Plesk event handlers. The event triggers every time a WordPress website is registered in the WordPress Toolkit after performed scan for WordPress installations or after installation via the Application catalog.
* [*] The WordPress installation procedure was simplified and streamlined.
* [*] The procedure for the installation of WordPress plugins and themes on newly created WordPress websites was simplified and streamlined.
* [-] Under certain circumstances, the administrator's webmail address was displayed incorrectly in WordPress Toolkit. (EXTWPTOOLK-490)
* [-] Importing a WordPress website resulted in an error if no hosting was configured for the parent domain. (EXTWPTOOLK-558)
* [-] In case of available major updates, administrators of WordPress websites with minor automatic updates enabled received daily notifications about installed updates even though these updates were not actually installed. Meanwhile, notifications about available updates were not delivered. (EXTWPTOOLK-561)
* [-] Cloning WordPress websites failed to preserve the source website's automatic update settings. (EXTWPTOOLK-600)

# 2.0.4 (04 May 2017)

* [*] The WP-CLI utility was updated to version 1.1.
* [*] Commands "list" and "info” were added to the WP-CLI utility. WordPress instances can be identified by the combination of "path" and "main-domain-id" (via WP-CLI as well). 
* [*] Titles of WordPress toolkit pages now display WordPress instance URL along with its name. 
* [-] If there were a large number of WordPress instances, during cloning, it took WordPress toolkit a lot of time to generate the list of available domains and subdomains. (EXTWPTOOLK-505)
* [-] There was no warning message that the destination WordPress instance will be replaced by the source one during synchronization. (EXTWPTOOLK-493)
* [-] During synchronization, database tables prefixes were changed even if users selected to synchronize only files. (EXTWPTOOLK-457)
* [-] Error messages were displayed in the panel log after the first WordPress instance installation. (EXTWPTOOLK-454)
* [-] If autoupdate settings were turned on in WordPress toolkit, and later they were changed manually in the configuration file, WordPress toolkit autoupdate settings were not changed accordingly. (EXTWPTOOLK-452) 
* [-] During new APS WordPress installations, the instances were marked as not secure because database tables prefixes were also marked as not secure. (EXTWPTOOLK-395)
* [-] If during WordPress installation the page was refreshed, WordPress installation started again. (EXTWPTOOLK-365)
* [-] If during WordPress installation wordpress.org was not accessible from the Plesk server and the necessary data was not stored in WordPress toolkit cache, Plesk displayed an error message that was not explicit. (EXTWPTOOLK-361)
* [-] WordPress Toolkit was able to generate invalid database table prefixes starting with numbers in exponential notation (for example, 0E70IaqpI). (EXTWPTOOLK-111)
* [-] Context help from all WordPress toolkit screen states did not redirect users to the WordPress related pages in Documentation and Help Portal. (EXTWPTOOLK-6)
* [-] If WordPress Toolkit scanned for new WordPress instances and at least one of new instances was corrupt, scanning was performed with errors and not all new instances were found. (EXTWPTOOLK-477)

# 2.0.3 (13 April 2017)

* [-] A WordPress site could not be cloned if "wp-config.php" file had non UTF-8 encoding. (EXTWPTOOLK-492)
* [-] A WordPress site was cloned incorrectly (some URLs of a clone site referred to the source) if values of "siteurl" and "home" were not the same. (EXTWPTOOLK-488)

# 2.0.2 (30 March 2017)

* [*] A WordPress site installed on a subdomain can now be cloned to a new subdomain of the same domain.
* [-] A WordPress site could not be displayed in browser without manual configuration after cloning to a domain with "Preferred domain" set to a WWW-prefixed URL. (EXTWPTOOLK-474)
* [-] A WordPress site could not be displayed in browser without manual configuration if it was installed on a domain with "Preferred domain" set to a WWW-prefixed URL. (EXTWPTOOLK-472)
* [-] Automatic login to WordPress failed if "Preferred domain" in the domain's hosting settings was set to another URL than the URL of the WordPress instance (for example to a WWW-prefixed URL while the instance had an URL without WWW prefix). (EXTWPTOOLK-470)
* [-] WordPress sites could not be synchronized if proc_open was disabled in PHP settings of the source or destination domain. (EXTWPTOOLK-466)
* [-] A WordPress site could not be cloned if proc_open was disabled in PHP settings of the source or destination domain. (EXTWPTOOLK-456)

# 2.0.1 (27 March 2017)

* [-] A WordPress instance installed via the Application Catalog had a database prefix marked as non-secure. (EXTWPTOOLK-463)
* [-] Automatic login to WordPress failed if the instance was installed using non-secure HTTP and the "Permanent SEO-safe 301 redirect from HTTP to HTTPS" option was enabled in the hosting settings of the domain. (EXTWPTOOLK-462) 
* [-] If an URL of a cloned WordPress instance ended with a slash after registering the instance in WordPress Toolkit, this URL did not change to a new one after cloning. (EXTWPTOOLK-461)
* [-] A page for managing a WordPress instance could not be opened in WordPress Toolkit if the instance used an external MySQL server database not registered in Plesk. (EXTWPTOOLK-460)
* [-] Slashes were present at the end of the URL of a WordPress instance installed via the Applications Catalog. (EXTWPTOOLK-458)
* [-] WordPress could not be installed if proc_open was disabled in a domain's PHP settings. (EXTWPTOOLK-455)

# 2.0.0 (23 March 2017)

* [+] WordPress sites can now be cloned between domains or subscriptions.
* [+] A WordPress site's data (including files and/or database) can be synchronized with another WordPress site.
* [+] A WordPress site can now be imported from another server. The Plesk Migrator extension is required for this functionality.
* [+] Search engine indexing can now be enabled or disabled for a WordPress site.
* [+] The events of creating and removing WordPress instances can now be processed by Plesk.
* [+] It is now possible to enable debugging options for a WordPress site.
* [*] Automatic updates can now be configured to install only the minor (security) updates.
* [*] The WordPress instance management page was improved to display more clear and detailed information.
* [*] The process of WordPress installation is now faster and has more detailed reporting.
* [-] During WordPress installation, WordPress Toolkit did not check if a database with the same name and database user already exists. (EXTWPTOOLK-423)
* [-] During installing WordPress on additional domains in Plesk for Windows, the "write/modify" permissions to the "wp-content" folder were not set automatically. As a result, images and themes of the WordPress installation could not be managed. (EXTWPTOOLK-419)
* [-] When switching to another WordPress instance from a WordPress instance settings dialog, the list of other instances was displayed without URLs. (EXTWPTOOLK-407)
* [-] In some cases, a confusing error message was displayed after WordPress installation was completed. (EXTWPTOOLK-343)
* [-] If MySQL server data directory in Plesk for Windows was changed so that it differed from the location of MySQL server executable files, WordPress could not be installed. (EXTWPTOOLK-326)
* [-] The "wp-config.php" file of a WordPress instance installed via WordPress Toolkit did not contain the "multisite" string, therefore it was inconvenient to enable multi-site WordPress. (EXTWPTOOLK-322)
* [-] When the Keychain for API Secret Keys and WordPress Toolkit extensions were installed in Plesk for Linux, reseller could not log in to Plesk. (EXTWPTOOLK-317)
* [-] Two quick WordPress installations run one by one on a domain, could lead to conflicts.(EXTWPTOOLK-288)
* [-] If an error occurred during WordPress installation, the full error description was not displayed in the maximized progress dialog. (EXTWPTOOLK-286)
* [-] During WordPress installation, the progress dialog was initially displayed minimized without showing information about the installation, and the list of WordPress instances did not refresh after the installation completion. (EXTWPTOOLK-285)
* [-] After renaming a domain with installed WordPress the "Site Address (URL)" parameter in WordPress was not changed. (EXTWPTOOLK-250)
* [-] If the value of the "Preferred domain" parameter was changed for the domain with installed WordPress, the automatic log in to WordPress from the Plesk user interface failed. (EXTWPTOOLK-249)
* [-] When access to WordPress Toolkit was restricted in Plesk configuration, an unclear error message was shown when trying to open WordPress Toolkit. (EXTWPTOOLK-237)
* [-] The "Update" and "View details" links were displayed merged in the Themes and Plugins tabs. (EXTWPTOOLK-141)
* [-] The "Owner" column in the list of WordPress installations contained a broken link if a subscription belonged to the Plesk administrator. (EXTWPTOOLK-33)
* [-] In some cases, WordPress sites were updated automatically even if automatic updates were disabled in their settings. (EXTWPTOOLK-20)
