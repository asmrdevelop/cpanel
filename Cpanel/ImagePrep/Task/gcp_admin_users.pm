
# cpanel - Cpanel/ImagePrep/Task/gcp_admin_users.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::ImagePrep::Task::gcp_admin_users;

use cPstrict;

use parent 'Cpanel::ImagePrep::Task';
use Cpanel::Imports;
use Cpanel::AccessIds::ReducedPrivileges ();
use Cpanel::ImagePrep::Common            ();
use Cpanel::Slurper                      ();
use Cpanel::Sys::Group                   ();

use Try::Tiny;

=head1 NAME

Cpanel::ImagePrep::Task::gcp_admin_users - An implementation subclass of Cpanel::ImagePrep::Task. See parent class for interface.

=cut

sub _description {
    return <<EOF;
A repair only task (not needed for pre- and post-snapshot) for a specific
problem that occurred with cPanel GCP images in the past.
EOF
}

sub _type { return 'repair only' }

sub _pre {
    my ($self) = @_;

    # Nothing necessary in pre stage, but we can't mark it is not applicable here, because it may be needed in post.
    # It will still be marked as not applicable in non-repair cases due to repair_only.
    return $self->PRE_POST_OK;
}

sub _post {
    my ($self) = @_;

    my @groups           = qw(google-sudoers adm);
    my @known_key_pieces = qw(
      iB7b6YkIN+QJCdLZvZFZT7fAto0=
      5nb52R4lW7zthg+SqHBCkC9XHjE=
    );

    if ( !-e Cpanel::ImagePrep::Common::GCLOUD_INSTANCE_FILE() ) {
        $self->loginfo('Not on GCP');
        return $self->PRE_POST_NOT_APPLICABLE;
    }

    my %relevant_groups;
    my %members;
    for my $group (@groups) {
        my ( undef, undef, undef, $members_str ) = $self->common->_getgrnam($group);
        if ($members_str) {
            $relevant_groups{$group} = 1;
            for my $member ( split / /, $members_str ) {
                $members{$member} = 1;
            }
        }
    }

    if ( !%members ) {
        $self->loginfo('No relevant groups found for GCP');
        return $self->PRE_POST_NOT_APPLICABLE;
    }

    my @found;
    for my $user ( sort keys %members ) {
        my $homedir = ( $self->common->_getpwnam($user) )[7];
        my $file    = "$homedir/.ssh/authorized_keys";
        my $remove_from_group;
        Cpanel::AccessIds::ReducedPrivileges::call_as_user(
            $user,
            sub {
                my $authorized_keys = try { Cpanel::Slurper::read($file) };
                if ( !$authorized_keys ) {
                    return;    # nothing else to do under call_as_user
                }
                for my $piece (@known_key_pieces) {
                    if ( $authorized_keys =~ /\Q$piece\E/ ) {
                        $self->common->_unlink($file);
                        if ( my $error = $! ) {
                            die "Failed to remove authorized_keys file for $user ($file): $error\n";
                        }
                        if ( open my $fh, '>', "$homedir/README" ) {
                            print {$fh} <<EOF;
Due to a misconfiguration, the cPanel image build process for Google
Cloud Platform erroneously added this user.

As part of an automated cleanup process, we deleted the user’s
.ssh/authorized_keys file and removed the user from the google-sudoers
and adm groups. We retained the account and home directory as
a precaution against potential data loss from overaggressive
deletion. Please feel free to delete the account yourself if you’ve
confirmed that it is not needed.
EOF
                            close $fh;
                        }
                        push @found, $user;
                        $remove_from_group = 1;
                        last;
                    }
                }
            },
        );

        if ($remove_from_group) {
            for my $group ( sort keys %relevant_groups ) {
                try {
                    my $group = Cpanel::Sys::Group->load($group);
                    if ( $group->is_member($user) ) {
                        $group->remove_member($user);
                    }
                }
                catch {
                    die "Failed to check/remove '$user' from group '$group': $_\n";
                };
            }
        }
    }

    if ( !@found ) {
        $self->loginfo('No erroneous admin users were found');
        return $self->PRE_POST_NOT_APPLICABLE;
    }

    $self->loginfo('Revoked authorized keys and group membership for erroneous admin user');
    return $self->PRE_POST_OK;
}

1;
