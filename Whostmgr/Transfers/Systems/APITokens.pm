package Whostmgr::Transfers::Systems::APITokens;

# cpanel - Whostmgr/Transfers/Systems/APITokens.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Imports;

use Cpanel::JSON       ();
use Cpanel::LoadFile   ();
use Cpanel::LoadModule ();

use Whostmgr::Transfers::Systems::APITokens::Backend ();

use Try::Tiny;

use parent 'Whostmgr::Transfers::Systems';

=head1 NAME

Whostmgr::Transfers::Systems::APITokens - A Transfer Systems module to restore a user's api tokens

=head1 SYNOPSIS

    use Whostmgr::Transfers::Systems::APITokens;

    my $transfer = Whostmgr::Transfers::Systems::APITokens->new(
         utils => $whostmgr_transfers_utils_obj,
         archive_manager => $whostmgr_transfers_archivemanager_obj,
    );
    $transfer->unrestricted_restore();

=head1 DESCRIPTION

This module implements a C<Whostmgr::Transfers::Systems> module. It is responsible for restoring the
api tokens for a given user.

=head1 METHODS

=cut

=head2 get_phase()

Override the default phase for a C<Whostmgr::Transfers::Systems> module.

=cut

sub get_phase {
    return 100;
}

=head2 get_prereq()

Override the default prereq for a C<Whostmgr::Transfers::Systems> module.

=cut

sub get_prereq {
    return ['PostRestoreActions'];
}

=head2 get_summary()

Provide a summary of what this module is supposed to do.

=cut

sub get_summary {
    my ($self) = @_;
    return [ $self->_locale()->maketext('The [asis,APITokens] module restores the [asis,API] tokens for an account.') ];
}

=head2 get_restricted_available()

Mark this module as available for retricted restores.

=cut

sub get_restricted_available {
    return 1;
}

=head2 unrestricted_restore()

The function that actually does the work of restoring the token file for a user.
It will only restore a tokens file if it exists in the packages.
This method is also aliased to C<restricted_restore>.

B<Returns>: C<1>

=cut

sub unrestricted_restore {
    my ($self) = @_;

    my $extractdir = $self->{'_archive_manager'}->trusted_archive_contents_dir();

    my $newuser = $self->{'_utils'}->local_username();

    my %service_token_data;

    # “tokens” is the old name for the WHM tokens file, from back when
    # WHM was the only service that used authn tokens. That datastore
    # was a raw copy of a file from the token storage datastore,
    # which contained a root-level “tokens” hash.
    #
    for my $filename (qw( cpanel whostmgr tokens )) {
        my $svc_name;

        if ( $filename eq 'tokens' ) {

            $svc_name = 'whostmgr';

            # Don’t look for “tokens” if we already have “whostmgr”.
            next if $service_token_data{$svc_name};
        }
        else {
            $svc_name = $filename;
        }

        my $archive_tokens_file = "$extractdir/api_tokens/$filename";

        my $tdata_json = Cpanel::LoadFile::load_if_exists($archive_tokens_file);
        next if !$tdata_json;

        my $tokens_hr = Cpanel::JSON::Load($tdata_json);

        $tokens_hr = $tokens_hr->{'tokens'} if $filename eq 'tokens';

        next if !$tokens_hr || !%$tokens_hr;

        $self->start_action("Restoring APITokens ($svc_name)");

        my $module = "Cpanel::Security::Authn::APITokens::Write::$svc_name";
        Cpanel::LoadModule::load_perl_module($module);

        my $validate_module = "Cpanel::Security::Authn::APITokens::Validate::$svc_name";
        Cpanel::LoadModule::load_perl_module($validate_module);

        my $tokens_obj = $module->new( { user => $newuser } );

        my $existing_tokens_hr = $tokens_obj->read_tokens();

        for my $token_hash ( keys %$tokens_hr ) {
            my $token_data_hr = $tokens_hr->{$token_hash};

            my $token_name = $token_data_hr->{'name'};

            if ( $token_data_hr->{'expires_at'} && $token_data_hr->{'expires_at'} < time() ) {

                # Skip tokens that have already expired
                # as they should be expunged anyways
                $self->utils()->add_skipped_item( locale()->maketext( 'The [asis,API] token “[_1]” expired on [datetime,_2,date_format_medium] at [datetime,_2,time_format_medium] [asis,UTC]. Because the token has expired, the system cannot restore it.', $token_name, $token_data_hr->{'expires_at'} ) );
                next;
            }

            my $new_name;

            if ( my $old_token_obj_by_hash = $existing_tokens_hr->{$token_hash} ) {

                # If the hash conflicts, then we always clobber the existing
                # token, but we report the clobberage differently.

                if ( $token_name eq $old_token_obj_by_hash->get_name() ) {
                    $self->out( locale()->maketext( 'The “[_1]” token already exists. Overwriting …', $token_name ) );
                }
                else {
                    $self->out( locale()->maketext( 'The archive’s “[_1]” token matches the account’s “[_2]” token. Overwriting …', $token_name, $old_token_obj_by_hash->get_name() ) );
                }
            }
            elsif ( my $old_token_obj_by_name = $tokens_obj->get_token_details_by_name($token_name) ) {
                $new_name = Whostmgr::Transfers::Systems::APITokens::Backend::find_new_name(
                    $tokens_obj,
                    $validate_module->MAX_LENGTH(),
                    $token_name,
                );

                # sanity check:
                die "should have changed $new_name" if $new_name eq $token_name;

                $self->out( locale()->maketext( 'The archive’s “[_1]” token mismatches the account’s token of the same name. Restoring the archive’s token as “[_2]” …', $token_name, $new_name ) );
            }

            $new_name //= $token_name;

            $tokens_obj->import_token_hash(
                {
                    token_hash => $token_hash,
                    %$token_data_hr,
                    name => $new_name,
                }
            );

            $existing_tokens_hr = $tokens_obj->read_tokens();
        }

        $tokens_obj->save_changes_to_disk();
    }

    return 1;
}

*restricted_restore = *unrestricted_restore;

1;
