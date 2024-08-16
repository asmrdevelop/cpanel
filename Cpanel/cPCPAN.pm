package Cpanel::cPCPAN;

# cpanel - Cpanel/cPCPAN.pm                        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

our $startdir;

sub new {
    my $class = shift;
    my $self  = {};
    bless $self, $class;
    $self->{'hasperlexpect'} = 0;
    $self->{'defaultcount'}  = 0;

    if ($>) {
        require Cpanel::PwCache;
        my $homedir = ( Cpanel::PwCache::getpwuid($>) )[7];

        # Removed workaround from case 3072.
        $self->{'basedir'} = $homedir;
    }
    else {
        $self->{'basedir'} = '/home';
    }

    if ( !-e $self->{'basedir'} ) {

        print "Creating missing directory $self->{'basedir'}\n";

        my $mask = $self->{'basedir'} eq '/home' ? '0755' : '0700';
        mkdir $self->{'basedir'}, oct $mask;

        if ( !-d $self->{'basedir'} ) {
            die "Failed to created directory: $!";
        }
    }

    require Cwd;
    $startdir = Cwd::fastcwd();

    chdir( $self->{'basedir'} ) || die "Could not chdir $self->{'basedir'}: $!";

    if ( !-e '.cpan' ) {
        mkdir '.cpan', 0755;
    }

    umask(0022);

    unless ($>) {
        chdir('/usr/local/cpanel') || die "Could not chdir /usr/local/cpanel: $!";
    }

    return $self;
}

sub _mergeconfig {
    my ( $r1, $r2 ) = @_;
    foreach ( keys %{$r1} ) {
        $r2->{$_} = $r1->{$_};
    }
}

sub list_available {
    my ($self) = @_;
    require Cpanel::cPCPAN::List;
    require Cpanel::cPCPAN::Init;    # PPI USE OK -- used for init_cfg
    $self->init_cfg();
    goto &Cpanel::cPCPAN::List::list_available;
}

sub search {
    my ($self) = @_;
    require Cpanel::cPCPAN::List;
    require Cpanel::cPCPAN::Init;    # PPI USE OK -- used for init_cfg
    $self->init_cfg();
    goto &Cpanel::cPCPAN::List::search;
}

sub list_installed {
    require Cpanel::cPCPAN::Installed;
    goto &Cpanel::cPCPAN::Installed::list_installed;
}

sub _make_ExtUtils_Installed {
    require Cpanel::cPCPAN::Installed;
    goto &Cpanel::cPCPAN::Installed::_make_ExtUtils_Installed;
}

sub uninstall {
    require Cpanel::cPCPAN::Installed;
    goto &Cpanel::cPCPAN::Installed::uninstall;
}

sub install {
    my ($self) = @_;
    require Cpanel::cPCPAN::Install;
    require Cpanel::cPCPAN::Init;    # PPI USE OK -- used for init_cfg
    $self->init_cfg();
    goto &Cpanel::cPCPAN::Install::install;
}

sub save_version_updates {
    require Cpanel::cPCPAN::Utils;
    goto &Cpanel::cPCPAN::Utils::save_version_updates;
}

sub get_root_module_from_file {
    require Cpanel::cPCPAN::Utils;
    goto &Cpanel::cPCPAN::Utils::get_root_module_from_file;
}

sub _cpanelservers {
    require Cpanel::cPCPAN::Utils;
    goto &Cpanel::cPCPAN::Utils::_cpanelservers;
}

sub _getAddressList {
    require Cpanel::cPCPAN::Utils;
    goto &Cpanel::cPCPAN::Utils::_getAddressList;
}

sub remove_tmp_basedir {
    return;
}

sub _version_is_newer_or_equal {
    my ( $have, $want )               = @_;
    my ( $have_version, $have_build ) = split( /_/, $have );
    my ( $want_version, $want_build ) = split( /_/, $want );
    $have_version = ( split( /-/, $have_version ) )[0];
    $want_version = ( split( /-/, $want_version ) )[0];

    require Cpanel::Version::Compare;
    if (

        Cpanel::Version::Compare::compare( $have_version, '>', $want_version ) || ( Cpanel::Version::Compare::compare( $have_version, '>=', $want_version )
            && $have_build >= $want_build )
    ) {
        return 1;

        # this version is ok
    }
    else {
        return 0;
    }
}

1;
