package Cpanel::Sys::Escalate;

# cpanel - Cpanel/Sys/Escalate.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Carp;

use Cpanel::OS         ();
use Cpanel::Binaries   ();
use Cpanel::LoadFile   ();
use Cpanel::Sys::Group ();

our $gl_bins_found = 0;
our %gl_bins;
our %gl_bins_broken;

sub _find_bins {

    # find all the binaries we'll need #
    $gl_bins{'su'}   ||= Cpanel::Binaries::path('su');
    $gl_bins{'sudo'} ||= Cpanel::Binaries::path('sudo');
    foreach my $bin (qw{ su sudo}) {
        if ( !-x $gl_bins{$bin} || !-u $gl_bins{$bin} ) {

            # add to the broken hash and remove from the available hash #
            $gl_bins_broken{$bin} = $bin;
            delete $gl_bins{$bin};
        }
        else {
            # cleanup in case of re-scanning bins #
            delete $gl_bins_broken{$bin};
        }
    }

    # don't do this again #
    $gl_bins_found = 1;
    return;
}

sub _su_allowing_root {
    return 1 if !Cpanel::OS::has_wheel_group();

    # su may be configured to not allow root to escalate! #
    return !( system( qw{ /bin/grep -qP }, '^\s*auth\s+(required|sufficient)\s+pam_rootok\.so\s*(#.+?)?$', '/etc/pam.d/su' ) >> 8 );
}

sub _su_allowing_general_users {
    return 1 if !Cpanel::OS::has_wheel_group();

    # su may be configured to allow any user to escalate up that has the root password #
    return !( system( qw{ /bin/grep -qP }, '^\s*auth\s+(include|substack)\s+system-auth\s*(#.+?)?$', '/etc/pam.d/su' ) >> 8 );
}

sub _su_requires_wheel_group {

    # su may require wheel membership #
    return !( system( qw{ /bin/grep -qP }, '^\s*auth\s+required\s+pam_wheel.so\s+use_uid\s*(#.+?)?$', '/etc/pam.d/su' ) >> 8 );
}

sub _su_allowing_wheel_users {

    # su can be enabled to allow or require wheel membership #
    return 1 if _su_requires_wheel_group();
    return 1 if !( system( qw{ /bin/grep -qP }, '^\s*auth\s+sufficient\s+pam_wheel.so\s+trust\s+use_uid\s*(#.+?)?$', '/etc/pam.d/su' ) >> 8 );
    return 0;
}

sub _su_allowing_escalation {

    # see if su is configured to allow any escalation #
    return 1 if _su_requires_wheel_group();
    return 1 if _su_allowing_general_users();

    # nope, at least not that we know of #
    return 0;
}

sub is_su_available {

    # returns true/false as to whether su works #

    # find binaries? #
    _find_bins() if !$gl_bins_found;

    return $gl_bins{'su'} ? 1 : 0;
}

sub is_su_broken {

    # returns true/false as to whether su works #

    # find binaries? #
    _find_bins() if !$gl_bins_found;

    return $gl_bins_broken{'su'} ? 1 : 0;
}

sub get_list_of_su_users {

    # returns a list of users that can su... #

    # find binaries? #
    _find_bins() if !$gl_bins_found;

    # is su available? #
    return [] if !$gl_bins{'su'};

    if ( _su_requires_wheel_group() ) {
        my $group  = Cpanel::Sys::Group->load( Cpanel::OS::sudoers() );
        my $groups = $group->get_members();

        # root may not be a member of wheel...  :| #
        push @{$groups}, 'root'
          if _su_allowing_root() && !grep { $_ eq 'root' } @{$groups};
        return $groups;
    }
    elsif ( _su_allowing_general_users() ) {

        # every user on the system! #
        my @etcpasswd = split /\n/, Cpanel::LoadFile::loadfile('/etc/passwd');
        return [ map { next if !m/\s*(.+?)\s*:/; $1 } @etcpasswd ];
    }
    elsif ( _su_allowing_root() ) {

        # only root #
        return ['root'];
    }

    # empty arrayref so caller doesn't have to handle undef case #
    return [];
}

sub can_user_su_to_root {

    # check a default configuration to see if the user can su #

    my $p_user = shift;

    # find binaries? #
    _find_bins() if !$gl_bins_found;

    # is su available? #
    return 0 if !$gl_bins{'su'};

    # check for root esclusively #
    return 1 if $p_user eq 'root' && _su_allowing_root();

    if ( _su_requires_wheel_group() ) {
        my $group = Cpanel::Sys::Group->load( Cpanel::OS::sudoers() );
        return 0 if !$group->is_member($p_user);
    }
    elsif ( !_su_allowing_general_users() ) {
        return 0;
    }

    # should be good #

    return 1;
}

sub sudo_allowing_root {

    # root may not be configured! #
    return !( system( qw{ /bin/grep -qP }, '^\s*root\s+ALL\s*=\s*(\(ALL\)|.*?su\b.*?)(\s*NOPASSWD\s*:\s*)?(\s+ALL|.*?su\b.*?)?\s*(#.+?)?$', '/etc/sudoers' ) >> 8 );
}

sub sudo_allowing_wheel_users {

    # see if wheel users are allowed full root escalation #
    my $sudoers = Cpanel::OS::sudoers();
    return !( system( qw{ /bin/grep -qP }, '^\s*%' . $sudoers . '\s+ALL\s*=\s*(\(ALL\)|.*?su\b.*?)(\s*NOPASSWD\s*:\s*)?(\s+ALL|.*?su\b.*?)?\s*(#.+?)?$', '/etc/sudoers' ) >> 8 );
}

sub is_sudo_available {

    # returns true/false as to whether sudo works #

    # find binaries? #
    _find_bins() if !$gl_bins_found;

    return $gl_bins{'sudo'} ? 1 : 0;
}

sub is_sudo_broken {

    # returns true/false as to whether sudo works #

    # find binaries? #
    _find_bins() if !$gl_bins_found;

    return $gl_bins_broken{'sudo'} ? 1 : 0;
}

sub get_list_of_sudo_users {

    # returns a list of users that can sudo... #

    # find binaries? #
    _find_bins() if !$gl_bins_found;

    # is sudo available? #
    return [] if !$gl_bins{'sudo'};

    if ( sudo_allowing_wheel_users() ) {
        my $group  = Cpanel::Sys::Group->load( Cpanel::OS::sudoers() );
        my $groups = $group->get_members();

        # root may not be a member of wheel/sudo...  :| #
        push @{$groups}, 'root'
          if _su_allowing_root() && !grep { $_ eq 'root' } @{$groups};
        return $groups;
    }
    elsif (sudo_allowing_root) {

        # ONLY root! #
        return ['root'];
    }

    # empty arrayref so caller doesn't have to handle undef case #
    return [];
}

sub can_user_sudo_to_root {

    # check a default configuration to see if the user can sudo #

    my $p_user = shift;

    # find binaries? #
    _find_bins() if !$gl_bins_found;

    # is sudo available? #
    return 0 if !$gl_bins{'sudo'};

    # check for root exclusively #
    return 1 if $p_user eq 'root' && sudo_allowing_root();

    return 1 if $p_user =~ /^cp\d+\.ssh$/;

    if ( sudo_allowing_wheel_users() ) {
        my $group = Cpanel::Sys::Group->load( Cpanel::OS::sudoers() );
        return 0 if !$group->is_member($p_user);
    }
    else {
        # an un-supported method is used #
        return 0;
    }

    # should be good #

    return 1;
}

sub can_user_escalate_to_root {
    my $p_user = shift;

    # su or sudo? #
    return 1 if can_user_su_to_root($p_user);
    return 1 if can_user_sudo_to_root($p_user);

    # nope #
    return 0;
}

1;
