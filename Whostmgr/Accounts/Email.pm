package Whostmgr::Accounts::Email;

# cpanel - Whostmgr/Accounts/Email.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 FUNCTIONS

=cut

use strict;
use warnings;

use Try::Tiny;

use Cpanel::Autodie                          ();
use Cpanel::CommandQueue                     ();
use Cpanel::Config::CpUserGuard              ();
use Cpanel::ConfigFiles                      ();
use Cpanel::Email::Accounts::HoldMaintenance ();
use Cpanel::Email::Accounts::Paths           ();
use Cpanel::Exception                        ();
use Cpanel::FileUtils::Dir                   ();
use Cpanel::LoadModule                       ();
use Cpanel::PwCache                          ();
use Cpanel::Validate::EmailCpanel            ();

my ( $locale, $logger );

use constant {
    ADD    => 1,
    REMOVE => 0
};

sub _locale {
    Cpanel::LoadModule::load_perl_module('Cpanel::Locale');
    return ( $locale ||= Cpanel::Locale->get_handle() );
}

sub _logger {
    Cpanel::LoadModule::load_perl_module('Cpanel::Logger');
    return ( $logger ||= Cpanel::Logger->new() );
}

sub suspend_outgoing_email {
    my (%opts) = @_;
    my $user = $opts{'user'};

    _check_user_param($user);

    my $cpuser_guard = Cpanel::Config::CpUserGuard->new($user);
    $cpuser_guard->{'data'}{'OUTGOING_MAIL_SUSPENDED'} = time();
    $cpuser_guard->save();

    update_outgoing_mail_suspended_users_db( 'user' => $user, 'suspended' => 1 );
    return 1;
}

sub unsuspend_outgoing_email {
    my (%opts) = @_;
    my $user = $opts{'user'};

    _check_user_param($user);

    my $cpuser_guard = Cpanel::Config::CpUserGuard->new($user);
    delete $cpuser_guard->{'data'}{'OUTGOING_MAIL_SUSPENDED'};
    $cpuser_guard->save();
    update_outgoing_mail_suspended_users_db( 'user' => $user, 'suspended' => 0 );
    return 1;

}

sub update_outgoing_mail_suspended_users_db {
    my (%opts) = @_;
    $opts{'op'}   = delete $opts{'suspended'};
    $opts{'file'} = $Cpanel::ConfigFiles::OUTGOING_MAIL_SUSPENDED_USERS_FILE;
    return _update_outgoing_mail_users_db(%opts);
}

sub _update_outgoing_mail_users_db {
    my (%opts) = @_;

    my $user = $opts{'user'};
    _check_user_param($user);

    my @missing = grep { !length $opts{$_} } qw(op file);

    if ( scalar @missing > 1 ) {
        die Cpanel::Exception::create( 'MissingParameters', [ names => \@missing ] );
    }
    elsif (@missing) {
        die Cpanel::Exception::create( 'MissingParameter', [ name => $missing[0] ] );
    }

    my $op   = $opts{'op'};
    my $file = $opts{'file'};

    require Cpanel::StringFunc::File;
    if ($op) {
        return Cpanel::StringFunc::File::addlinefile( $file, $user );
    }
    return Cpanel::StringFunc::File::remlinefile( $file, $user );
}

sub hold_outgoing_email {
    my (%opts) = @_;
    my $user = $opts{'user'};

    _check_user_param($user);

    my $cpuser_guard = Cpanel::Config::CpUserGuard->new($user);
    $cpuser_guard->{'data'}{'OUTGOING_MAIL_HOLD'} = time();
    $cpuser_guard->save();

    update_outgoing_mail_hold_users_db( 'user' => $user, 'hold' => 1 );
    return 1;
}

sub release_outgoing_email {
    my (%opts) = @_;
    my $user = $opts{'user'};

    _check_user_param($user);

    my $cpuser_guard = Cpanel::Config::CpUserGuard->new($user);
    delete $cpuser_guard->{'data'}{'OUTGOING_MAIL_HOLD'};
    $cpuser_guard->save();
    update_outgoing_mail_hold_users_db( 'user' => $user, 'hold' => 0 );
    return 1;

}

sub update_outgoing_mail_hold_users_db {
    my (%opts) = @_;
    $opts{'op'}   = delete $opts{'hold'};
    $opts{'file'} = $Cpanel::ConfigFiles::OUTGOING_MAIL_HOLD_USERS_FILE;
    return _update_outgoing_mail_users_db(%opts);
}

=head2 I<Class>::rename_user

Replaces a username with a new one in the outgoing hold and suspension files

=head3 Arguments

=over 4

=item oldname - string - The username of the user who is being renamed

=item newname - string - The new username for the user

=back

=head3 Returns

This function returns 1 if the rename was successful, or dies.

=head3 Exceptions

=over

=item - If oldname or newname isn't passed

=back

=cut

sub rename_user {
    my (%opts) = @_;

    my @expected = qw(oldname newname);
    _verify_params( 'opts' => \%opts, 'expected' => \@expected );
    my ( $oldname, $newname ) = @opts{@expected};

    if ( $oldname eq 'root' || $newname eq 'root' ) {
        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” is not a valid user for this operation.', ['root'] );
    }

    #TODO: Put these operations into a CommandQueue object so that we
    #roll back in the event of failure. cf. COBRA-6609

    _replace_in_config_files( 'match' => qr<\A\Q$oldname\E\z>, 'replace' => $newname );

    my $old_user_limits_dir = "$Cpanel::Email::Accounts::Paths::EMAIL_SUSPENSIONS_BASE_PATH/$oldname";
    my $new_user_limits_dir = "$Cpanel::Email::Accounts::Paths::EMAIL_SUSPENSIONS_BASE_PATH/$newname";

    Cpanel::Autodie::rename_if_exists( $old_user_limits_dir, $new_user_limits_dir );

    return 1;
}

=head2 I<Class>::change_domain

Replaces a domain with a new one in the outgoing hold and suspension files

=head3 Arguments

=over 4

=item user      - string - The username of the owner of the domain being changed

=item olddomain - string - The domain name that is being changed

=item newdomain - string - The new domain

=back

=head3 Returns

This function returns 1 if the domain change was successful, or dies.

=head3 Exceptions

=over

=item - If user, olddomain, or newdomain aren't passed

=back

=cut

sub change_domain {
    my (%opts) = @_;

    my @expected = qw(user olddomain newdomain);
    _verify_params( 'opts' => \%opts, 'expected' => \@expected );
    my ( $user, $olddomain, $newdomain ) = @opts{@expected};

    if ( _replace_in_config_files( 'match' => qr<\@\Q$olddomain\E\z>, 'replace' => "\@$newdomain" ) ) {

        my $limits_ref = _open_limits_ref( 'user' => $user );

        # _open_limits_ref returns undef if the update would be a noop because the file doesn't exist
        if ($limits_ref) {
            if ( defined $limits_ref->get_data()->{$olddomain} ) {
                $limits_ref->get_data()->{$newdomain} = delete $limits_ref->get_data()->{$olddomain};
                $limits_ref->save_and_close_or_die();
            }
            else {
                $limits_ref->close_or_die();
            }
        }

    }

    return 1;
}

sub _verify_params {

    my (%opts) = @_;

    my %real_opts = %{ $opts{'opts'} };
    my @expected  = @{ $opts{'expected'} };

    #sanity
    my @missing = grep { !defined $real_opts{$_} } @expected;

    if ( scalar @missing > 1 ) {
        die Cpanel::Exception::create( 'MissingParameters', [ names => \@missing ] );
    }
    elsif (@missing) {
        die Cpanel::Exception::create( 'MissingParameter', [ name => $missing[0] ] );
    }

    return;
}

sub _replace_in_config_files {

    my (%opts) = @_;

    my @expected = qw(match replace);
    _verify_params( 'opts' => \%opts, 'expected' => \@expected );
    my ( $match, $replace ) = @opts{@expected};

    my @files = (
        $Cpanel::ConfigFiles::OUTGOING_MAIL_HOLD_USERS_FILE,
        $Cpanel::ConfigFiles::OUTGOING_MAIL_SUSPENDED_USERS_FILE,
    );

    my $replaced = 0;

    require Cpanel::StringFunc::File;
    for my $file (@files) {

        #The interface to this function (along with other functions
        #in this module) doesn’t allow for a distinction between
        #nonexistence of the file and failure to update the file.
        #We just have to trust that the user will see the log file.
        $replaced += Cpanel::StringFunc::File::replacelinefile( $file, $match, $replace );
    }

    return $replaced;
}

sub _check_user_param {
    my ($user) = @_;

    die Cpanel::Exception::create( 'MissingParameter', [ 'name' => 'user' ] ) if !length $user;
    if ( $user eq 'root' ) {
        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” is not a valid user for this operation.', ['root'] );
    }

    return;
}

=head2 I<Class>::suspend_mailuser_outgoing_email

Suspends outgoing email messages for an email subaccount.

=head3 Arguments

=over 4

=item user  - string - The user who owns the email subaccount

=item email - string - The email subaccount to suspend

=back

=head3 Returns

This function returns 1 if the email was suspended, undef if the email was already suspended, or dies.

=head3 Exceptions

=over

=item - If user or email aren't passed

=item - If OUTGOING_MAIL_SUSPENDED_USERS_FILE isn't updated successfully

=back

=cut

sub suspend_mailuser_outgoing_email {
    my (%opts) = @_;
    $opts{'op'}    = ADD;
    $opts{'file'}  = $Cpanel::ConfigFiles::OUTGOING_MAIL_SUSPENDED_USERS_FILE;
    $opts{'param'} = 'suspended';
    return _update_mailuser_suspended_or_hold(%opts);
}

=head2 I<Class>::unsuspend_mailuser_outgoing_email

Unsuspends outgoing email messages for an email subaccount.

=head3 Arguments

=over 4

=item user  - string - The user who owns the email subaccount

=item email - string - The email subaccount to unsuspend

=back

=head3 Returns

This function returns 1 if the email was unsuspended, undef if the email was not suspended, or dies.

=head3 Exceptions

=over

=item - If user or email aren't passed

=item - If it fails to update OUTGOING_MAIL_SUSPENDED_USERS_FILE

=back

=cut

sub unsuspend_mailuser_outgoing_email {
    my (%opts) = @_;
    $opts{'op'}    = REMOVE;
    $opts{'file'}  = $Cpanel::ConfigFiles::OUTGOING_MAIL_SUSPENDED_USERS_FILE;
    $opts{'param'} = 'suspended';
    return _update_mailuser_suspended_or_hold(%opts);
}

=head2 I<Class>::hold_mailuser_outgoing_email

Holds outgoing email messages for an email subaccount.

=head3 Arguments

=over 4

=item user  - string - The user who owns the email subaccount

=item email - string - The email subaccount to hold

=back

=head3 Returns

This function returns 1 if the email was held, undef if the email was already held, or dies.

=head3 Exceptions

=over

=item - If user or email aren't passed

=item - If it fails to update OUTGOING_MAIL_HOLD_USERS_FILE

=back

=cut

sub hold_mailuser_outgoing_email {
    my (%opts) = @_;
    $opts{'op'}    = ADD;
    $opts{'file'}  = $Cpanel::ConfigFiles::OUTGOING_MAIL_HOLD_USERS_FILE;
    $opts{'param'} = 'hold';
    return _update_mailuser_suspended_or_hold(%opts);
}

=head2 I<Class>::releases_mailuser_outgoing_email

Releases outgoing email messages for an email subaccount.

=head3 Arguments

=over 4

=item user  - string - The user who owns the email subaccount

=item email - string - The email subaccount to hold

=back

=head3 Returns

This function returns 1 if the email was released, undef if the email was not being held, or dies.

=head3 Exceptions

=over

=item - If user or email aren't passed

=item - If OUTGOING_MAIL_HOLD_USERS_FILE isn't updated successfully

=back

=cut

sub release_mailuser_outgoing_email {
    my (%opts) = @_;
    $opts{'op'}    = REMOVE;
    $opts{'file'}  = $Cpanel::ConfigFiles::OUTGOING_MAIL_HOLD_USERS_FILE;
    $opts{'param'} = 'hold';
    return _update_mailuser_suspended_or_hold(%opts);
}

=head2 I<Class>::get_mailuser_outgoing_email_hold_count

Gets the count of outbound email messages that are being held in the mail queue for the specified email address

=head3 Arguments

=over 4

=item email - string - The email subaccount to get the count for

=back

=head3 Returns

This function returns the count of held messages or dies.

=head3 Exceptions

=over

=item - If email isn't passed

=back

=cut

sub get_mailuser_outgoing_email_hold_count {

    my (%opts) = @_;

    die Cpanel::Exception::create( 'MissingParameter', [ name => 'email' ] ) if !length $opts{'email'};

    return scalar _get_held_message_ids( $opts{'email'} ) || 0;
}

=head2 I<Class>::delete_mailuser_outgoing_email_holds

Queues a background process that deletes outbound email messages that are being held in the mail queue for the specified email address.

=head3 Arguments

=over 4

=item email - string - The email subaccount to delete the held messages for

=back

=head3 Returns

This function returns the count of held messages queued for delete or dies.

=head3 Exceptions

=over

=item - If email isn't passed

=back

=cut

sub delete_mailuser_outgoing_email_holds {

    my (%opts) = @_;

    die Cpanel::Exception::create( 'MissingParameter', [ name => 'email' ] ) if !length $opts{'email'};

    my @ids = _get_held_message_ids( $opts{'email'} );

    if ( scalar @ids ) {
        require Whostmgr::Exim;

        my $remove_opts = { 'msgids' => \@ids };

        if ( $opts{'release_after_delete'} ) {

            die Cpanel::Exception::create( 'MissingParameter', [ name => 'user' ] ) if !length $opts{'user'};

            $remove_opts->{'do_after'} = sub {
                Cpanel::Email::Accounts::HoldMaintenance::remove_hold_files_for_sender( $opts{'email'} );
                release_mailuser_outgoing_email( 'user' => $opts{'user'}, 'email' => $opts{'email'} );
            }

        }
        else {
            $remove_opts->{'do_after'} = sub {
                Cpanel::Email::Accounts::HoldMaintenance::remove_hold_files_for_sender( $opts{'email'} );
            }
        }

        my ( $ret, $msg ) = Whostmgr::Exim::remove_messages_mail_queue($remove_opts);
        die $msg if !$ret;
    }

    return scalar @ids || 0;
}

sub _get_held_message_ids {

    my ($email) = @_;

    my $hold_path = join '/', $Cpanel::Email::Accounts::Paths::EMAIL_HOLDS_BASE_PATH, $email;

    my $nodes_ar = Cpanel::FileUtils::Dir::get_directory_nodes_if_exists($hold_path);
    if ($nodes_ar) {
        return grep { Cpanel::Autodie::exists("$hold_path/$_") && -f _ } @$nodes_ar;
    }

    return ();
}

sub _update_mailuser_suspended_or_hold {

    my (%opts) = @_;

    my $user = $opts{'user'};
    _check_user_param($user);

    my @missing = grep { !length $opts{$_} } qw(email op file param);

    if ( scalar @missing > 1 ) {
        die Cpanel::Exception::create( 'MissingParameters', [ names => \@missing ] );
    }
    elsif (@missing) {
        die Cpanel::Exception::create( 'MissingParameter', [ name => $missing[0] ] );
    }

    if ( $opts{'param'} ne 'suspended' && $opts{'param'} ne 'hold' ) {
        die Cpanel::Exception::create( 'InvalidParameter', "The “[_1]” argument must be “[_2]” or “[_3]”.", [ 'param', 'suspended', 'hold' ] );
    }

    my ( $email, $op, $file, $param ) = @opts{qw(email op file param)};

    my $cq = Cpanel::CommandQueue->new();
    my $did_something;

    $cq->add(
        sub { $did_something = _update_outgoing_mail_limits_store( user => $user, email => $email, $param => $op ); },
        sub { _update_outgoing_mail_limits_store( user => $user, email => $email, $param => !$op ) if $did_something; }
    );

    $cq->add(
        sub {
            if ($did_something) {

                my $result = _update_outgoing_mail_users_db( user => $email, op => $op, file => $file );

                # _update_outgoing_mail_users_db returns 1 on success, 0 if the db didn't change, undef on error
                # Since we already updated the user's store, 0 would mean the DB was already in the desired state, so only pay attention to undef
                if ( !defined $result ) {
                    die Cpanel::Exception::create(
                        'IO::FileWriteError',
                        [
                            path  => $file,
                            error => _locale()->maketext("Failed to update the mail server configuration.")
                        ]
                    );
                }
            }
        }
    );

    $cq->run();

    return $did_something;
}

sub _update_outgoing_mail_limits_store {
    my (%opts)    = @_;
    my $user      = $opts{'user'};
    my $email     = $opts{'email'};
    my $suspended = $opts{'suspended'};
    my $hold      = $opts{'hold'};

    my $limits_ref = _open_limits_ref(%opts);

    # _open_limits_ref returns undef if the update would be a noop because we're
    # releasing or unsuspending and the limits directory or file doesn't exist.
    if ( !$limits_ref ) {
        return;
    }

    my ( $account, $domain ) = Cpanel::Validate::EmailCpanel::get_name_and_domain($email);

    my $did_something;

    if ( defined $suspended ) {
        if ( $suspended && !$limits_ref->get_data()->{$domain}{'suspended'}{$account} ) {
            $limits_ref->get_data()->{$domain}{'suspended'}{$account} = 1;
            $did_something = 1;
        }
        elsif ( !$suspended && $limits_ref->get_data()->{$domain}{'suspended'}{$account} ) {
            delete $limits_ref->get_data()->{$domain}{'suspended'}{$account};
            $did_something = 1;
        }
    }

    if ( defined $hold ) {
        if ( $hold && !$limits_ref->get_data()->{$domain}{'hold'}{$account} ) {
            $limits_ref->get_data()->{$domain}{'hold'}{$account} = 1;
            $did_something = 1;
        }
        elsif ( !$hold && $limits_ref->get_data()->{$domain}{'hold'}{$account} ) {
            delete $limits_ref->get_data()->{$domain}{'hold'}{$account};
            $did_something = 1;
        }
    }

    if ($did_something) {
        $limits_ref->save_and_close_or_die();
    }
    else {
        $limits_ref->close_or_die();
    }

    return $did_something;
}

sub _open_limits_ref {

    my (%opts) = @_;

    my $user      = $opts{'user'};
    my $suspended = $opts{'suspended'};
    my $hold      = $opts{'hold'};

    my $user_limits_dir = _setup_directory(%opts);

    # _setup_directory returns undef if the update would be a noop because we're
    # releasing or unsuspending and the limits directory or file doesn't exist.
    if ( !$user_limits_dir ) {
        return;
    }

    my $limits_file = "$user_limits_dir/$Cpanel::Email::Accounts::Paths::EMAIL_SUSPENSIONS_FILE_NAME";

    # Don't create the limits file if we're just going to write empty JSON
    return if !Cpanel::Autodie::exists($limits_file) && !$suspended && !$hold;

    my $limits_ref;

    require Cpanel::Transaction::File::JSON;
    try {
        $limits_ref = Cpanel::Transaction::File::JSON->new(
            'path'        => $limits_file,
            'permissions' => 0640,
            'ownership'   => [ 'root', $user ]
        );

        $limits_ref->get_data();
    }
    catch {
        _logger()->warn( "The system encountered an error while reading the “$limits_file” file: " . Cpanel::Exception::get_string($_) );
        $limits_ref->set_data( {} )
    };

    if ( 'HASH' ne ref $limits_ref->get_data() ) {
        $limits_ref->set_data( {} );
    }

    return $limits_ref;
}

sub _setup_directory {

    my (%opts) = @_;

    my $user      = $opts{'user'};
    my $hold      = $opts{'hold'};
    my $suspended = $opts{'suspended'};

    my $base_path_perms = 0751;

    my $gid = ( Cpanel::PwCache::getpwnam($user) )[3] or die "User “$user” has no GID!";

    Cpanel::Autodie::exists($Cpanel::Email::Accounts::Paths::EMAIL_SUSPENSIONS_BASE_PATH);

    if ( -d _ ) {
        Cpanel::Autodie::chmod( $base_path_perms, $Cpanel::Email::Accounts::Paths::EMAIL_SUSPENSIONS_BASE_PATH );
    }
    else {

        # Don't create the directory if we're just going to write empty JSON
        return if !$suspended && !$hold;
        Cpanel::Autodie::mkdir( $Cpanel::Email::Accounts::Paths::EMAIL_SUSPENSIONS_BASE_PATH, $base_path_perms );
    }

    my $user_limits_dir = "$Cpanel::Email::Accounts::Paths::EMAIL_SUSPENSIONS_BASE_PATH/$user";

    my $user_limits_perms = 0750;

    Cpanel::Autodie::exists($user_limits_dir);

    if ( -d _ ) {
        Cpanel::Autodie::chmod( $user_limits_perms, $user_limits_dir );
    }
    else {

        # Don't create the directory if we're just going to write empty JSON
        return if !$suspended && !$hold;
        Cpanel::Autodie::mkdir( $user_limits_dir, $user_limits_perms );

    }

    Cpanel::Autodie::chown( 0, $gid, $user_limits_dir );

    return $user_limits_dir;
}
1;
