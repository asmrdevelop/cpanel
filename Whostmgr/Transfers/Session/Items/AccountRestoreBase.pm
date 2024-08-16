package Whostmgr::Transfers::Session::Items::AccountRestoreBase;

# cpanel - Whostmgr/Transfers/Session/Items/AccountRestoreBase.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

#----------------------------------------------------------------------

use Cpanel::AcctUtils::Account ();
use Cpanel::DiskCheck          ();
use Cpanel::FileUtils::Path    ();

use parent qw( Whostmgr::Transfers::Session::Item );

our $VERSION = '1.0';

use constant {
    _IS_USER_USABLE => 1,
};

#----------------------------------------------------------------------

# cf. Whostmgr::Transfers::Session::Item’s prevalidate_or_die().
sub _prevalidate ( $, $, $input_hr ) {
    require Whostmgr::Transfers::Utils::LinkedNodes;

    for my $worker_type ( keys %Whostmgr::Transfers::Utils::LinkedNodes::WORKER_TYPE_CAPABILITY_PARAMETER ) {
        my $param = $Whostmgr::Transfers::Utils::LinkedNodes::WORKER_TYPE_CAPABILITY_PARAMETER{$worker_type};

        my $str = $input_hr->{$param};

        if ( length $str ) {
            require Whostmgr::Transfers::Utils::LinkedNodes;

            Whostmgr::Transfers::Utils::LinkedNodes::validate_restore_handler_parameter( $str, $worker_type );
        }
    }

    return;
}

sub check_restore_disk_space {
    my ($self) = @_;

    # Case 176937 - --force should override disk space checks
    if ( $self->{'session_obj'}->{'ignore_disk_space'} ) {
        return ( 1, 'ok' );
    }

    my $source = $self->get_restore_source_path();
    my $target = ( Cpanel::FileUtils::Path::dir_and_file_from_path($source) )[0];

    $self->{'input'}{'size'} ||= $self->size();
    my $source_sizes = $self->_generate_source_sizes_from_source_and_known_sizes();
    return Cpanel::DiskCheck::target_has_enough_free_space_to_fit_source_sizes( 'source_sizes' => $source_sizes, 'target' => $target );
}

sub _generate_source_sizes_from_source_and_known_sizes {
    my ($self) = @_;

    my $source       = $self->get_restore_source_path();
    my $source_sizes = Cpanel::DiskCheck::calculate_source_sizes($source);

    my $can_stream  = $self->session()->can_stream();
    my $skiphomedir = $self->{'input'}{'skiphomedir'};
    my $input_size  = $self->{'input'}{'size'}  || 1;
    my $input_files = $self->{'input'}{'files'} || 1;

    # calculate_source_sizes does not expand an archive. If we have input data
    # about the size or number of files of the account we use it if it’s larger
    # than what we know about, but only if streaming isn't supported AND skiphomedir isn't on
    # otherwise, we'll be unable to transfer some accounts due to the estimated size inflation of the
    # archive size vs streaming size.
    my @source_sizes_with_input_data;
    my $total_size   = 0;
    my $saw_streamed = 0;
    foreach my $source_size (@$source_sizes) {
        foreach my $key ( keys %$source_size ) {
            my $value;
            if ( $key eq 'files' ) {
                $value = $input_files > $source_size->{$key} ? $input_files : $source_size->{$key};
            }
            else {
                if ( $can_stream || $skiphomedir ) {
                    $value = $source_size->{$key};
                }
                else {
                    $value = $input_size > $source_size->{$key} ? $input_size : $source_size->{$key};
                }
                $total_size += $value;
            }
            push @source_sizes_with_input_data, { $key => $value };

            # This will currently never trigger, but I'm leaving it here as a bit of defensive programming
            # if calculate_source_sizes ever changes to include the streamed size then this could save us from a bug.
            $saw_streamed = 1 if $key eq 'streamed';
        }
    }

    # If we're streaming the homedir calculate_source_sizes doesn't know about the streamed size of things.
    if ( $can_stream && !$skiphomedir && !$saw_streamed && $input_size > $total_size ) {
        push @source_sizes_with_input_data, { 'streamed' => ( $input_size - $total_size ) };
    }

    return \@source_sizes_with_input_data;
}

# If we’re creating a new account, then we need $username not to exist
# locally. If we’re NOT creating a new account, we need $username TO exist.
# This function verifies that.
#
sub _validate_local_username_against_system_state ( $self, $username ) {

    # One or the other of these must be true, but NOT both.
    my $acct_exists   = !!Cpanel::AcctUtils::Account::accountexists($username);
    my $do_createacct = !$self->{'input'}{'skipaccount'};

    if ( not( $acct_exists xor $do_createacct ) ) {
        if ($acct_exists) {
            return ( 0, $self->_locale()->maketext( "A user named “[_1]” already exists on this server.", $username ) );
        }
        else {
            return ( 0, $self->_locale()->maketext( "No user named “[_1]” exists on this server.", $username ) );
        }
    }

    return ( 1, "$username is available." );
}

1;
