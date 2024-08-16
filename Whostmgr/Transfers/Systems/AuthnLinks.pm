package Whostmgr::Transfers::Systems::AuthnLinks;

# cpanel - Whostmgr/Transfers/Systems/AuthnLinks.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::Exception                     ();
use Cpanel::FileUtils::Dir                ();
use Cpanel::JSON                          ();
use Cpanel::Security::Authn::User::Modify ();
use Cpanel::AccessControl                 ();
use Cpanel::AcctUtils::Lookup::Webmail    ();
use Try::Tiny;

use base qw(
  Whostmgr::Transfers::Systems
);

sub get_phase {
    return 100;
}

sub get_prereq {
    return ['PostRestoreActions'];
}

sub get_summary {
    my ($self) = @_;
    return [ $self->_locale()->maketext('This restores the account’s external authentication links.') ];
}

sub get_restricted_available {
    return 1;
}

sub _restore_v1 {
    my ( $self, $username, $archive_authnlinks_file, $authn_links ) = @_;

    foreach my $protocol ( keys %{$authn_links} ) {
        my $protocol_hr = $authn_links->{$protocol};

        if ( ref $protocol_hr ne 'HASH' ) {
            $self->warn("Corrupt datastore at “$archive_authnlinks_file”! (“$protocol” should be a HASH reference, not $protocol_hr)\n");
            next;
        }

        foreach my $provider_name ( keys %$protocol_hr ) {
            my $provider_hr = $protocol_hr->{$provider_name};

            if ( ref $provider_hr ne 'HASH' ) {
                $self->warn("Corrupt datastore at “$archive_authnlinks_file”! (“$protocol”:“$provider_name” should be a HASH reference, not $provider_hr)\n");
                next;
            }

            foreach my $subject_unique_identifier ( keys %$provider_hr ) {
                my $user_info = $provider_hr->{$subject_unique_identifier};

                my $err;
                try {
                    # Account link notification will die in whostmgr context for now.
                    local $Cpanel::App::appname = 'cpaneld';
                    Cpanel::Security::Authn::User::Modify::add_authn_link_for_user( $username, $protocol, $provider_name, $subject_unique_identifier, $user_info );
                }
                catch {
                    $err = $_;
                };
                if ($err) {
                    $self->warn(
                        $self->_locale()->maketext(
                            'The system failed to restore the “[_1]” protocol link with the subject “[_2]” for the provider “[_3]” because of an error: [_4]',
                            $protocol, $subject_unique_identifier, $provider_name, Cpanel::Exception::get_string($err)
                        )
                    );
                }
                else {
                    $self->out(
                        $self->_locale()->maketext(
                            'The system restored the “[_1]” protocol link with the subject “[_2]” for the provider “[_3]”.',
                            $protocol, $subject_unique_identifier, $provider_name
                        )
                    );
                }
            }
        }
    }

    return 1;
}

sub unrestricted_restore {
    my ($self) = @_;

    my $archive_authnlinks_dir = $self->_links_dir();

    return 1 if !-d $archive_authnlinks_dir;

    $self->start_action('Restoring AuthnLinks');

    my $nodes_ar       = Cpanel::FileUtils::Dir::get_directory_nodes($archive_authnlinks_dir);
    my $local_username = $self->{'_utils'}->local_username();
    my $db_re          = qr<\.\Qdb\E\z>;

    foreach my $node (@$nodes_ar) {
        next if $node !~ $db_re;

        my $username_to_restore = $node;
        $username_to_restore =~ s/$db_re//;

        if ( !Cpanel::AcctUtils::Lookup::Webmail::is_strict_webmail_user($username_to_restore) ) {
            $username_to_restore = $local_username;
        }
        elsif ( !Cpanel::AccessControl::user_has_access_to_account( $local_username, $username_to_restore ) ) {
            $self->{'_utils'}->add_skipped_item( $self->_locale()->maketext( 'The system could not restore the authentication links for “[_1]” because it belongs to another user.', $username_to_restore ) );
            next;
        }

        my $archive_authnlinks_file = "$archive_authnlinks_dir/$node";
        my $authn_links             = Cpanel::JSON::LoadFile($archive_authnlinks_file);

        my $db_version = delete $authn_links->{'__VERSION'};

        if ( $db_version eq '1.0' ) {
            $self->_restore_v1( $username_to_restore, $archive_authnlinks_file, $authn_links );
        }
        else {
            die Cpanel::Exception->create( 'The external authentication links file, “[_1]”, indicates its schema version as version “[_2]”. The system cannot restore the data in this file because it does not know how to interpret that schema version.', [ $archive_authnlinks_file, $db_version ] );
        }
    }

    return 1;
}

sub _links_dir {
    my ($self) = @_;

    my $extractdir = $self->{'_archive_manager'}->trusted_archive_contents_dir();

    return "$extractdir/authnlinks";
}

*restricted_restore = \&unrestricted_restore;

1;
