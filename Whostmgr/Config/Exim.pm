package Whostmgr::Config::Exim;

# cpanel - Whostmgr/Config/Exim.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

our %exim_files = (
    '/etc/exim.conf'                                           => { 'special' => 'archive' },
    '/etc/exim.conf.local'                                     => { 'special' => 'dry_run' },
    '/etc/exim.conf.localopts'                                 => { 'special' => 'dry_run' },
    '/etc/exim.conf.localopts.shadow'                          => { 'special' => 'dry_run' },
    '/etc/mail/spamassassin/BAYES_POISON_DEFENSE.cf'           => { 'special' => "present" },
    '/etc/mail/spamassassin/CPANEL.cf'                         => { 'special' => "present" },
    '/etc/mail/spamassassin/KAM.cf'                            => { 'special' => "present" },
    '/etc/mail/spamassassin/P0f.cf'                            => { 'special' => "present" },
    '/etc/mail/spamassassin/deadweight.cf'                     => { 'special' => "present" },
    '/etc/mail/spamassassin/deadweight2.cf'                    => { 'special' => "present" },
    '/etc/mail/spamassassin/deadweight2_meta.cf'               => { 'special' => "present" },
    '/etc/mail/spamassassin/deadweight2_sub.cf'                => { 'special' => "present" },
    '/etc/mail/spamassassin/kam_heavyweights.cf'               => { 'special' => "present" },
    '/etc/global_spamassassin_enable'                          => { 'special' => "present" },
    '/var/cpanel/config/email/query_apache_for_nobody_senders' => { 'special' => "present" },
    '/var/cpanel/config/email/trust_x_php_script'              => { 'special' => "present" },
    '/var/cpanel/custom_mailhelo'                              => { 'special' => "present" },
    '/var/cpanel/custom_mailips'                               => { 'special' => "present" },
    '/var/cpanel/per_domain_mailips'                           => { 'special' => "present" },
    '/var/cpanel/use_rdns_for_helo'                            => { 'special' => "present" },
    '/etc/backupmxhosts'                                       => { 'special' => "present" },
    '/etc/cpanel_mail_netblocks'                               => { 'special' => "present" },
    '/etc/greylist_trusted_netblocks'                          => { 'special' => "present" },
    '/etc/neighbor_netblocks'                                  => { 'special' => "present" },
    '/etc/senderverifybypasshosts'                             => { 'special' => "present" },
    '/etc/cpanel_exim_system_filter'                           => { 'special' => "present" },
    '/etc/skipsmtpcheckhosts'                                  => { 'special' => "present" },
    '/etc/spammeripblocks'                                     => { 'special' => "present" },
    '/etc/blocked_incoming_email_country_ips'                  => { 'special' => "present" },
    '/etc/blocked_incoming_email_countries'                    => { 'special' => "present" },
    '/etc/blocked_incoming_email_domains'                      => { 'special' => "present" },
    '/etc/trustedmailhosts'                                    => { 'special' => "present" },
    '/etc/spammers'                                            => { 'special' => "present" },
    '/etc/exim_suspended_list'                                 => { 'special' => "present" },
    '/var/cpanel/rbl_info'                                     => { 'special' => 'dir', 'archive_dir' => 'cpanel/smtp/exim/rbl_info' },
);

1;
