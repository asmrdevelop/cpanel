package Install::SSHD;

# cpanel - install/SSHD.pm                         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use base qw( Cpanel::Task );

use Cpanel::Sys::Group              ();
use Whostmgr::Services::SSH::Config ();

our $VERSION = '1.0';

=head1 NAME

Install::SSHD - upcp post-install task module for SSH daemon configuration.

=head1 DESCRIPTION

This Cpanel::Task module configured the SSH daemon on cPanel & WHM systems.

=over 1

=item Type: Fresh Install, Sanity

=item Frequency: once

=item EOL: never

=back

=head1 METHODS

=over

=item new()

Constructor for Install::SSHD objects.

=cut

exit __PACKAGE__->runtask() unless caller;

sub new {
    my $proto = shift;
    my $self  = $proto->SUPER::new;

    $self->set_internal_name('sshd');

    return $self;
}

=item perform()

Method to do the actual work of the Install::SSHD task.

=over

=item *

Creates the cpaneldemo group and add current demo accounts to it.

=item *

Creates the cpanelsuspended group and add current suspended accounts to it.

=item *

Updates the sshd_config to deny access to the cpaneldemo and cpanelsuspended groups.

=back

=cut

sub perform {
    my $self = shift;

    $self->do_once(
        version => 'sec-247-sshd',
        eol     => 'never',
        code    => sub {
            $self->_update_demo_accounts();
            $self->_update_suspended_accounts();
            $self->_update_sshd_config();
        }
    );

    return 1;
}

sub _update_sshd_config {
    my $self = shift;

    my $config_obj         = Whostmgr::Services::SSH::Config->new();
    my $denygroups_setting = $config_obj->get_config('DenyGroups');

    my %denied_groups;
    if ( defined $denygroups_setting && ref $denygroups_setting eq 'ARRAY' ) {
        %denied_groups = map { $_ => 1 } @{$denygroups_setting};
    }
    elsif ( defined $denygroups_setting ) {
        $denied_groups{$denygroups_setting} = 1;
    }

    $denied_groups{cpaneldemo}      = 1;
    $denied_groups{cpanelsuspended} = 1;
    my $denied_groups_setting = join( ' ', sort keys %denied_groups );

    eval { $config_obj->set_config( { DenyGroups => $denied_groups_setting } ); };
    if ($@) {
        print "SSHD configuration changes failed. Sending notification.\n";
        $config_obj->notify_failure();
        return 0;
    }
    return $self->_restart_sshd();
}

sub _restart_sshd {
    my $self = shift;
    system('/usr/local/cpanel/scripts/restartsrv_sshd');
    return 1;
}

sub _update_demo_accounts {
    my $self      = shift;
    my $group_obj = Cpanel::Sys::Group->load_or_create('cpaneldemo');
    if ( open my $fh, "<", "/etc/demousers" ) {
        while ( my $account = readline($fh) ) {
            chomp $account;
            next unless length $account;
            next unless getpwnam($account);
            next unless -e "/var/cpanel/users/$account";
            next if $group_obj->is_member($account);
            $group_obj->add_member($account);
        }
        close $fh;
    }
    return 1;
}

sub _update_suspended_accounts {
    my $self      = shift;
    my $group_obj = Cpanel::Sys::Group->load_or_create('cpanelsuspended');

    if ( opendir my $dh, "/var/cpanel/suspended" ) {
        while ( my $account = readdir($dh) ) {
            next if ( $account =~ /\A\.\.?\z/ );
            next unless getpwnam($account);
            next unless -e "/var/cpanel/users/$account";
            next if $group_obj->is_member($account);
            $group_obj->add_member($account);
        }
        closedir $dh;
    }

    return 1;
}

=back

=cut

1;
