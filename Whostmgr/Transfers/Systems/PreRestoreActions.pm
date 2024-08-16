package Whostmgr::Transfers::Systems::PreRestoreActions;

# cpanel - Whostmgr/Transfers/Systems/PreRestoreActions.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::ConfigFiles        ();
use Cpanel::Hooks              ();
use Cpanel::Exception          ();
use Cpanel::SafeRun::Object    ();
use Cpanel::AcctUtils::Account ();
use Cpanel::LoadModule         ();

use Try::Tiny;

use base qw(
  Whostmgr::Transfers::Systems
);

our $PRERESTORE_SCRIPT = "$Cpanel::ConfigFiles::CPANEL_ROOT/scripts/prerestoreacct";

sub get_summary {
    my ($self) = @_;
    return [ $self->_locale()->maketext('This performs pre-restoration actions and cleanups.') ];
}

sub get_restricted_available {
    return 1;
}

sub get_notes {
    my ($self) = @_;
    return [ $self->_locale()->maketext('This module temporarily lifts the account’s quota and runs custom pre-restoration scripts.') ];
}

*restricted_restore = \&unrestricted_restore;

sub unrestricted_restore {
    my ($self) = @_;

    my $user    = $self->newuser();
    my $olduser = $self->olduser();    # case 113733: Used only externally

    my $extractdir = $self->extractdir();

    if ( Cpanel::AcctUtils::Account::accountexists($user) ) {
        $self->start_action("Temporarily lifting quota for existing user to ensure that all data is transferred.");

        Cpanel::LoadModule::load_perl_module('Cpanel::Quota::Blocks');
        my $blocks = 0;
        try {
            'Cpanel::Quota::Blocks'->new()->set_user($user)->set_limits_if_quotas_enabled( { soft => $blocks, hard => $blocks } );
        }
        catch {
            $self->out( Cpanel::Exception::get_string($_) );
        };

    }

    if ( -x $PRERESTORE_SCRIPT ) {
        $self->start_action('Running prerestore script');
        my $run = Cpanel::SafeRun::Object->new( 'program' => $PRERESTORE_SCRIPT, 'args' => [ $user, $olduser, $extractdir ] );    # case 113733: Used only externally
        my $err = $run->stderr();
        my $out = $run->stdout();
        $self->out($out)  if $out;
        $self->warn($err) if $err;
    }

    my ( $hook_result, $hook_msgs ) = Cpanel::Hooks::hook(
        {
            'category' => 'PkgAcct',
            'event'    => 'Restore',
            'stage'    => 'postExtract',
            'blocking' => 1,
        },
        $self->{'_utils'}{'flags'}
    );
    my $hooks_msg = join "\n", @$hook_msgs;
    $self->{'_utils'}->die("Hook denied execution of event: $hooks_msg") if !$hook_result;

    return 1;
}

sub get_phase {
    return 1;
}

sub get_relative_time {
    return 5;
}

sub get_prereq {
    return [];
}
1;
