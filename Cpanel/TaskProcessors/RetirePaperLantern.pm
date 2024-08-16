package Cpanel::TaskProcessors::RetirePaperLantern;

# cpanel - Cpanel/TaskProcessors/RetirePaperLantern.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;
use Cpanel::Logger ();

{
    # Updates current users that have PL as default themes to use Jupiter instead
    package Cpanel::TaskProcessors::RetirePaperLantern::PLUsersToJupiter;

    use parent qw(
      Cpanel::TaskQueue::FastSpawn
    );
    use Cpanel::LoadModule ();

    sub _do_child_task {
        my ( $self, $task, $logger ) = @_;

        my @pl_users_updated = _update_pl_users();

        if ( scalar @pl_users_updated ) {
            $logger->info( "The following Paper Lantern users have been updated to use Jupiter as default theme instead: " . join( ', ', sort @pl_users_updated ) . "\n" );
        }

        return;
    }

    sub _update_pl_users {
        local $ENV{REMOTE_USER} = "root";

        Cpanel::LoadModule::load_perl_module('Whostmgr::ACLS');
        Cpanel::LoadModule::load_perl_module('Whostmgr::Accounts::List');
        Whostmgr::ACLS::init_acls();
        my ( $count, $ar ) = Whostmgr::Accounts::List::listaccts();
        return unless $count;

        Cpanel::LoadModule::load_perl_module('Cpanel::Config::CpUserGuard');
        my @updated_users = map {
            my ($user) = $_->{'user'};
            my $guard = Cpanel::Config::CpUserGuard->new($user);
            $guard->{'data'}{'RS'} = 'jupiter';
            $guard->save();
            $user;
        } grep { $_->{'theme'} eq 'paper_lantern' } @$ar;

        if ( scalar @updated_users ) {
            Cpanel::LoadModule::load_perl_module('Cpanel::AccessIds::ReducedPrivileges');
            Cpanel::LoadModule::load_perl_module('Cpanel::NVData');

            foreach my $u (@updated_users) {
                _set_nvdata($u);
            }
        }

        return @updated_users;
    }

    sub _set_nvdata {
        my ($user) = @_;
        Cpanel::AccessIds::ReducedPrivileges::call_as_user(
            sub {
                Cpanel::NVData::_set( "migrated_to_jupiter", 1 );
            },
            $user
        );

        return;
    }
}

{
    # Updates packages that have PL as themes to use Jupiter instead
    package Cpanel::TaskProcessors::RetirePaperLantern::PLPkgsToJupiter;

    use parent qw(
      Cpanel::TaskQueue::FastSpawn
    );
    use Cpanel::LoadModule ();

    sub _do_child_task {
        my ( $self, $task, $logger ) = @_;

        my @pl_pkgs_updated = _update_pl_pkgs($logger);

        if ( scalar @pl_pkgs_updated ) {
            $logger->info( "The following Paper Lantern packages have been updated to use Jupiter as default theme instead: " . join( ', ', sort @pl_pkgs_updated ) . "\n" );
        }

        return;
    }

    sub _update_pl_pkgs {
        my ($logger) = @_;
        local $ENV{REMOTE_USER} = "root";

        Cpanel::LoadModule::load_perl_module('Whostmgr::ACLS');
        Cpanel::LoadModule::load_perl_module('Whostmgr::Packages::Fetch');
        Whostmgr::ACLS::init_acls();
        my $pkgs_hr = Whostmgr::Packages::Fetch::fetch_package_list( "want" => "all" );

        my @updated_packages;
        foreach my $pkg ( keys %{$pkgs_hr} ) {
            next unless $pkgs_hr->{$pkg}->{'CPMOD'} eq 'paper_lantern';
            $pkgs_hr->{$pkg}->{'CPMOD'} = 'jupiter';
            next unless _save_package( $pkg, $pkgs_hr->{$pkg}, $logger );
            push @updated_packages, $pkg;
        }

        return @updated_packages;
    }

    sub _save_package {
        my ( $pkg, $data, $logger ) = @_;

        Cpanel::LoadModule::load_perl_module('Cpanel::SafeFile');
        Cpanel::LoadModule::load_perl_module('Whostmgr::Packages::Load');

        my $package_dir = Whostmgr::Packages::Load::package_dir();
        my $pkglock     = Cpanel::SafeFile::safeopen( \*PKG, '+<', $package_dir . $pkg );
        if ( !$pkglock ) {
            $logger->warn("Could not edit ${package_dir}$pkg");
            return 0;
        }

        seek( PKG, 0, 0 );
        foreach my $pkgitem ( sort keys %{$data} ) {
            next if !$pkgitem;
            next if ( $pkgitem eq '_PACKAGE_EXTENSIONS' );
            my $line = qq{$pkgitem=$data->{$pkgitem}};
            $line =~ s/[\r\n]//g;
            print PKG $line . "\n";
        }

        print PKG qq{_PACKAGE_EXTENSIONS=$data->{_PACKAGE_EXTENSIONS}\n};    # _PACKAGE_EXTENSIONS last in file.
        truncate( PKG, tell(PKG) );
        Cpanel::SafeFile::safeclose( \*PKG, $pkglock );

        return 1;
    }

}

sub to_register {
    return (
        [ 'paper_lantern_users_to_jupiter' => Cpanel::TaskProcessors::RetirePaperLantern::PLUsersToJupiter->new() ],
        [ 'paper_lantern_pkgs_to_jupiter'  => Cpanel::TaskProcessors::RetirePaperLantern::PLPkgsToJupiter->new() ],
    );
}

1;

__END__

=encoding utf-8

=head1 NAME

Cpanel::TaskProcessors::RetirePaperLantern - Task processors for the deprecation of Paper Lantern.

=head1 VERSION

This document describes Cpanel::TaskProcessors::RetirePaperLantern.

=head1 SYNOPSIS

    use Cpanel::TaskProcessors::RetirePaperLantern;

    # Update paper_lantern users to use jupiter as default theme instead. 
    Cpanel::ServerTasks::queue_task( ['Cpanel::TaskProcessors::RetirePaperLantern'], 'paper_lantern_users_to_jupiter' );

    # Update paper_lantern packages to use jupiter as default theme instead. 
    Cpanel::ServerTasks::queue_task( ['Cpanel::TaskProcessors::RetirePaperLantern'], 'paper_lantern_pkgs_to_jupiter' );

=head1 DESCRIPTION

This module provides methods that can be run as background processes to facilitate the eventual
removal of paper_lantern. These tasks are usually run as part of the cPanel update process.

=head1 INTERFACE

This module defines subclasses of L<Cpanel::TaskQueue::FastSpawn> and a package method.

=head2 Cpanel::TaskProcessors::RetirePaperLantern::to_register

Used by the L<Cpanel::TaskQueue::PluginManager> to register the included classes.

=head2 Cpanel::TaskProcessors::RetirePaperLantern::PLUsersToJupiter

This task updates user data files that have paper_lantern as default theme to use jupiter as
default theme instead. It should not update other items in the user data files, and should not
update user data files that have themes other than paper_lantern even if some of these themes
may be considered obsolete by cPanel. This task will also set the nvdata migrated_to_jupiter
to 1 for users that have been updated by this process. 

=head2 Cpanel::TaskProcessors::RetirePaperLantern::PLPkgsToJupiter

This task updates package files that have paper_lantern as default theme to use jupiter as
default theme instead. It should not update other items in the package files, even if some of
these items are now considered by cPanel to be invalid or obsolete. This task should not
update data files of users that have been assigned to these packages.

=head1 DEPENDENCIES

None

=head1 INCOMPATIBILITIES

None reported.
