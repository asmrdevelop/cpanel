package Cpanel::Services::Group;

# cpanel - Cpanel/Services/Group.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

my %SERVICE_GROUP_FOR = (
    'rsyslogd' => 'systemlogging',
    'syslogd'  => 'systemlogging',
);

sub get_service_group {
    my $service = shift;

    if ( exists $SERVICE_GROUP_FOR{$service} ) {
        return $SERVICE_GROUP_FOR{$service};
    }

    return $service;
}

1;

__END__

Some mutually exclusive services we place behind a generic name
like pure ftp and proftp, bind and nsd, etc.  For circumstances
where we do not have a generic facade,  this module can be used
to create logical groups.
