package Cpanel::Config::ConfigObj::Driver::QueryApacheForNobodySenders::META;

# cpanel - Cpanel/Config/ConfigObj/Driver/QueryApacheForNobodySenders/META.pm
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

# Avoids having to deal with locale information
# when all we care about is the driver name.
sub get_driver_name {
    return 'query_apache_for_nobody_senders';
}

sub content {
    my ($locale_handle) = @_;

    my $content = {
        'vendor' => 'cPanel, Inc.',
        'url'    => 'https://go.cpanel.net/featureshowcaseaskapachenobody',
        'name'   => {
            'short'  => "Query Apache for 'nobody' senders",
            'long'   => "Query Apache for 'nobody' senders",
            'driver' => get_driver_name(),
        },
        'since'    => '',
        'abstract' => qq{Query Apache For 'nobody' senders enables the mail delivery process to query the Apache server to determine the true sender of a message when the user who sent the message is 'nobody'. }
          . "This feature requires an additional connection to the webserver for each message that is sent with the user account “nobody” (PHPsuExec and mod_ruid2 disabled). This option is more secure, but not as fast as trusting X-PHP-Script headers.",
        'version' => $VERSION,
    };

    if ($locale_handle) {
        $content->{'name'}->{'short'} = $locale_handle->maketext('Query Apache for “nobody” senders.');
        $content->{'name'}->{'long'}  = $locale_handle->maketext('Query Apache for “nobody” senders.');
        $content->{'abstract'} =
            $locale_handle->maketext(qq{Query Apache for “nobody” senders enables the mail delivery process to query the Apache server to determine the true sender of a message when the user who sent the message is “nobody”.}) . ' '
          . $locale_handle->maketext("This feature requires an additional connection to the webserver for each message that is sent with the user account “nobody” (PHPsuExec and mod_ruid2 disabled). This option is more secure, but not as fast as trusting X-PHP-Script headers.");
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
