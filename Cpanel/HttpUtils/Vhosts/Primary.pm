package Cpanel::HttpUtils::Vhosts::Primary;

# cpanel - Cpanel/HttpUtils/Vhosts/Primary.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
#NOTE: Use this class for read/write operations ONLY.
#If you only need to read, then use PrimaryReader.
#----------------------------------------------------------------------

use strict;
use warnings;

use base 'Cpanel::HttpUtils::Vhosts::PrimaryReader';

use Cpanel::ConfigFiles                   ();
use Cpanel::ConfigFiles::Apache           ();
use Cpanel::Destruct                      ();
use Cpanel::LoadModule                    ();
use Cpanel::SafeDir::MK                   ();
use Cpanel::Transaction::File::LoadConfig ();
use Cpanel::Validate::IP::v4              ();
use File::Path::Tiny                      ();

my $FILE_HEADER = <<END;
#============
#NOTE: This file's format may change over time. The data here also goes
#through a non-trivial validation process before being written.
#To ensure stability, do not interact with this file directly;
#instead, use API calls to read and to set the data in this file.
#============
END

#----------------------------------------------------------------------
#Transaction stuff
sub new {
    my ($class) = @_;

    my $conf_dir = Cpanel::ConfigFiles::Apache->new()->dir_conf();
    if ( !-e $conf_dir ) {

        # logs on failure
        if ( !Cpanel::SafeDir::MK::safemkdir( $conf_dir, "0700" ) ) {
            Cpanel::LoadModule::load_perl_module('Cpanel::Locale');
            my $locale = Cpanel::Locale->get_handle();
            die $locale->maketext( 'The system failed to create the directory “[_1]” due to an error: [_2]', $conf_dir, $! );
        }
    }

    File::Path::Tiny::mk_parent($Cpanel::ConfigFiles::APACHE_PRIMARY_VHOSTS_FILE) or die "Could not create parent directory for “$Cpanel::ConfigFiles::APACHE_PRIMARY_VHOSTS_FILE”: $!\n";    # in case it is not already there, noop otherwise
    my $trans_obj = Cpanel::Transaction::File::LoadConfig->new(
        path      => $Cpanel::ConfigFiles::APACHE_PRIMARY_VHOSTS_FILE,
        delimiter => '=',
    );

    if ( !$trans_obj ) {
        Cpanel::LoadModule::load_perl_module('Cpanel::Locale');
        my $locale = Cpanel::Locale->get_handle();
        die $locale->maketext( 'The system failed to lock “[_1]” because of an unknown error.', $Cpanel::ConfigFiles::APACHE_PRIMARY_VHOSTS_FILE );
    }

    return bless { _original_pid => $$, _modified => 0, _transaction => $trans_obj }, $class;
}

#Don't bother getting rid of _transaction so we can still read it
#after we're done.
sub abort {
    my ($self) = @_;

    return 1 if !$self->{'_transaction'};

    my ( $ok, $msg ) = $self->{'_transaction'}->abort();

    return $ok ? 1 : ( 0, $msg );
}

sub close {
    my ($self) = @_;

    return 1 if !$self->{'_transaction'};

    my ( $ok, $msg ) = $self->abort();
    return ( 0, $msg ) if !$ok;

    $self->{'_transaction'} = undef;

    return 1;
}

sub save {
    my ($self) = @_;

    if ( !$self->{'_modified'} ) {
        return $self->close();
    }

    my ( $ok, $msg ) = $self->{'_transaction'}->save( header => $FILE_HEADER );

    return $ok ? 1 : ( 0, $msg );
}

#----------------------------------------------------------------------
#Un-setters (i.e., delete)

sub unset_primary_ssl_servername {
    my ( $self, $ip ) = @_;

    die "No IP!" if !$ip;    #Programmer error

    return _unset_primary_servername( $self, "$ip:SSL" );
}

sub unset_primary_non_ssl_servername {
    my ( $self, $ip ) = @_;

    die "No IP!" if !$ip;    #Programmer error

    return _unset_primary_servername( $self, $ip );
}

sub _unset_primary_servername {
    my ( $self, $key ) = @_;

    $self->{'_modified'} = 1;
    $self->{'_transaction'}->remove_entry($key);

    return;
}

#----------------------------------------------------------------------
#Setters

sub set_primary_ssl_servername {
    my ( $self, $ip, $servername ) = @_;

    die "No IP!" if !$ip;    #Programmer error

    # Silently ignore anything that is not an IPv4 address,
    # This will reject any IPv6 addresses, including any that
    # have been mangled due to bad parsing.
    # For the time being, we do not want any IPv6 addresses
    # ending up the the primary_virtual_hosts file
    return unless ( Cpanel::Validate::IP::v4::is_valid_ipv4($ip) );

    return _set_primary_servername( $self, "$ip:SSL", $servername );
}

sub set_primary_non_ssl_servername {
    my ( $self, $ip, $servername ) = @_;

    die "No IP!" if !$ip;    #Programmer error

    # See comment in set_primary_ssl_servername
    return unless ( Cpanel::Validate::IP::v4::is_valid_ipv4($ip) );

    return _set_primary_servername( $self, $ip, $servername );
}

sub _set_primary_servername {
    my ( $self, $key, $servername ) = @_;

    die "No servername!" if !$servername;    #Programmer error

    my $current_entry = $self->{'_transaction'}->get_entry($key);
    if ( !$current_entry || $current_entry ne $servername ) {
        $self->{'_transaction'}->set_entry( $key, $servername );
        $self->{'_modified'} = 1;
    }

    return;
}

sub DESTROY {
    my ($self) = @_;

    return if Cpanel::Destruct::in_dangerous_global_destruction();

    return unless $self->{'_original_pid'} && $$ == $self->{'_original_pid'};

    if ( $self->{'_transaction'} ) {
        my ( $ok, $msg ) = $self->abort();
        if ( !$ok ) {
            my $pkg = __PACKAGE__;
            warn "Error on auto-destroy instance of $pkg: $msg";
        }
    }

    return;
}

1;
