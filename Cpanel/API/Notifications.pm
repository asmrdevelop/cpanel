package Cpanel::API::Notifications;

# cpanel - Cpanel/API/Notifications.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::API    ();
use Cpanel::ExpVar ();
use Cpanel::News   ();

sub get_notifications_count {
    my ( $args, $result ) = @_;

    my $count = 0;
    for my $news_type (qw(global resold cpanel)) {
        $count++ if Cpanel::News::does_news_type_exist( type => $news_type );
    }

    $count++ if $ENV{'CPRESELLER'};

    my $disk_full = Cpanel::ExpVar::expvar('$disk_quota_is_full');
    if ($disk_full) {
        $count++;
        $result->data($count);    # the call below does not work if over quota
        return 1;
    }

    my $email_accounts = Cpanel::API::execute( 'Email', 'list_pops_with_disk', { 'no_suspend_check' => 1, 'no_human_readable_keys' => 1, 'nearquotaonly' => 1 } );
    $count++ if $email_accounts && $email_accounts->status && scalar( @{ $email_accounts->data() } );

    $result->data($count);

    return 1;
}

our %API = (
    get_notifications_count => { allow_demo => 1 },
);

1;
