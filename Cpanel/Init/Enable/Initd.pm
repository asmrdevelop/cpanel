package Cpanel::Init::Enable::Initd;

# cpanel - Cpanel/Init/Enable/Initd.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use Moo;
use cPstrict;

use Carp;
use Cpanel::SafeRun::Errors ();
use Cpanel::SafeRun::Simple ();

extends 'Cpanel::Init::Enable::Base';

has 'check_config' => ( is => 'rw', default => '/sbin/chkconfig' );
has 'runlevel' => (
    is      => 'ro',
    default => sub {
        my $runlevel = Cpanel::SafeRun::Simple::saferun('/sbin/runlevel');
        if ( length $runlevel ) {
            $runlevel =~ /(\d)/;
            $runlevel = $1 if $1;
        }
        return $runlevel;
    }
);

sub enable {
    my ( $self, $levels ) = @_;
    my $to_enable    = $self->enabled;
    my $check_config = $self->check_config;

    local $ENV{'LC_ALL'} = 'C';

    $levels ||= '35';
    while ( my $service = shift @{$to_enable} ) {
        Cpanel::SafeRun::Errors::saferunnoerror( $check_config, '--add', $service );
        Cpanel::SafeRun::Errors::saferunnoerror( $check_config, '--level', $levels, $service, 'on' );
        if ( !$self->is_enabled($service) ) {
            return 0;
        }
    }
    return 1;
}

sub disable {
    my ( $self, $levels ) = @_;
    my $to_disabled  = $self->disabled;
    my $check_config = $self->check_config;

    local $ENV{'LC_ALL'} = 'C';

    $levels ||= '35';
    while ( my $service = shift @{$to_disabled} ) {
        Cpanel::SafeRun::Errors::saferunnoerror( $check_config, '--level', $levels, $service, 'off' );
        if ( $self->is_enabled($service) ) {
            return 0;
        }
    }

    return 1;
}

# ror            0:on 1:on 2:on 3:on 4:on 5:on 6:on
sub is_enabled {
    my ( $self, $service ) = @_;

    local $ENV{'LC_ALL'} = 'C';

    my $check_config = $self->check_config;
    my $status       = Cpanel::SafeRun::Errors::saferunnoerror( $check_config, '--list', $service );
    $status = '' unless defined $status;

    my @status = split( /\s+/, $status );
    shift @status;
    my %status = map { $_ => 1 } @status;

    my $runlevel = $self->runlevel();

    if ( $runlevel && exists $status{"$runlevel:on"} ) {
        return 1;
    }
    else {
        return 0;
    }
}

1;

__END__

=head1 NAME

Cpanel::Init::Enable::Initd

=head1 DESCRIPTION

    Cpanel::Init::Enable::Initd enables and disables services for Red Hat.

=head1 INTERFACE

=head2 Methods

=over 4

=item enable

This method enables all the services that where enabled by the collect_enable method
the base class.

=item disable

This method disables all the services that where enabled by the collect_disable method
the base class.

=back
