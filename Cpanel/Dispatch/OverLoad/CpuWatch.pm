package Cpanel::Dispatch::OverLoad::CpuWatch;

# cpanel - Cpanel/Dispatch/OverLoad/CpuWatch.pm    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::LoadModule       ();
use Cpanel::StringFunc::Case ();

sub new {
    my ( $class, %OPTS ) = @_;

    if ( !length $OPTS{'pid'} ) {
        die Cpanel::Exception::create( 'MissingParameter', [ 'name' => 'pid' ] );
    }
    my $pid = $OPTS{'pid'};

    if ( $pid !~ m{^[0-9]+$} ) {
        die Cpanel::Exception::create( 'InvalidParameter', "The process id “[_1]” is not valid.", [$pid] );
    }

    return bless { 'pid' => $pid }, $class;
}

sub dispatch {
    my ($self) = @_;

    my $this_module = ( split( m{::}, scalar ref $self ) )[-1];

    if ( $> == 0 ) {
        my $icontact_namespace = "Cpanel::iContact::Class::OverLoad::$this_module";
        my $icontact_origin    = Cpanel::StringFunc::Case::ToLower($this_module);
        Cpanel::LoadModule::load_perl_module('Cpanel::Locale');
        Cpanel::LoadModule::load_perl_module('Cpanel::PsParser');
        Cpanel::LoadModule::load_perl_module($icontact_namespace);
        my $pid_info = Cpanel::PsParser::get_pid_info( $self->{'pid'} );
        if ( !$pid_info ) {
            Cpanel::LoadModule::load_perl_module('Cpanel::Exception');

            # If the pid dies between trigger the notification and now there is
            # no point in sending the notification.
            die Cpanel::Exception->create( "The system does not have a process with ID “[_1]”. It is possible that a process was running but has since ended.", [ $self->{'pid'} ] );
        }
        $icontact_namespace->new( user => 'root', 'origin' => $icontact_origin, %{$pid_info} );
    }
    else {
        my $adminbin_call = Cpanel::StringFunc::Case::ToUpper($this_module);
        Cpanel::LoadModule::load_perl_module('Cpanel::AdminBin::Call');
        Cpanel::AdminBin::Call::call( 'Cpanel', 'notify_call', 'NOTIFY_' . $adminbin_call, $self->{'pid'} );
    }

    return 1;
}

1;
