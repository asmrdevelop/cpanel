package Cpanel::Config::ConfigObj::Driver::SMTPRestrictions::META;

# cpanel - Cpanel/Config/ConfigObj/Driver/SMTPRestrictions/META.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use parent qw(Cpanel::Config::ConfigObj::Interface::Config::Version::v1);
our $VERSION = 1.1;

sub meta_version {
    return 1;
}

sub get_driver_name {
    return 'smtp_restrictions';
}

sub content {
    my ($locale_handle) = @_;

    my $content = {
        'vendor' => 'cPanel, Inc.',
        'url'    => 'https://go.cpanel.net/featureshowcasesmtprestrictions',
        'name'   => {
            'short'  => 'SMTP Restrictions',
            'long'   => 'SMTP Group Restrictions',
            'driver' => get_driver_name(),
        },
        'since'    => '',
        'abstract' => "This feature prevents users from bypassing the mail server to send mail, a common practice used by spammers. It will allow only the MTA (mail transport agent), mailman, and root to connect to remote SMTP servers.",
        'version'  => $VERSION,
    };

    if ($locale_handle) {
        $content->{'name'}->{'short'} = $locale_handle->maketext('[output,acronym,SMTP,Simple Mail Transfer Protocol] Restrictions');
        $content->{'name'}->{'long'}  = $locale_handle->maketext('[output,acronym,SMTP,Simple Mail Transfer Protocol] Group Restrictions');
        $content->{'abstract'}        = $locale_handle->maketext("This feature prevents users from bypassing the mail server to send mail, a common practice used by spammers.") . ' ' . $locale_handle->maketext("It will allow only the [output,acronym,MTA,Mail Transport Agent], [asis,mailman], and [asis,root] to connect to remote [output,acronym,SMTP,Simple Mail Transfer Protocol] servers.");
    }

    return $content;
}

sub showcase {
    return 0;
}

sub auto_enable {
    return 1;
}

1;
