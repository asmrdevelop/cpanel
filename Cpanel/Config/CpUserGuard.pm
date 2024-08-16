package Cpanel::Config::CpUserGuard;

# cpanel - Cpanel/Config/CpUserGuard.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Config::CpUserGuard

=head1 SYNOPSIS

    my $guard = Cpanel::Config::CpUserGuard->new( $username );

    $guard->set_worker_node( 'Mail', $alias, $token );

    $guard->unset_worker_node( 'Mail' );

    # Alas …
    my $cpuser_hr = $guard->{'data'};

    $cpuser_hr->{'notify_ssl_expiry'} = 1;

    # This die()s on failure.
    $guard->save();

    # … or:

    $guard->abort();

=head1 DESCRIPTION

All modifications to cpuser files should normally go through this
class.

=cut

#----------------------------------------------------------------------

use Cpanel::Destruct               ();
use Cpanel::Config::CpUser         ();
use Cpanel::Config::CpUser::Write  ();
use Cpanel::Config::LoadCpUserFile ();
use Cpanel::Debug                  ();

#----------------------------------------------------------------------

=head1 METHODS

=head2 $obj = I<CLASS>->new( $USERNAME )

Instantiates this class by locking the cpuser file.

The returned object will automatically close its lock on DESTROY.

=cut

sub new {
    my ( $class, $user ) = @_;

    my ( $data, $file, $lock, $is_locked ) = ( undef, undef, undef, 0 );

    my $cpuser = Cpanel::Config::LoadCpUserFile::_load_locked($user);
    if ( $cpuser && ref $cpuser eq 'HASH' ) {
        $data      = $cpuser->{'data'};
        $file      = $cpuser->{'file'};
        $lock      = $cpuser->{'lock'};
        $is_locked = defined $lock;
    }
    else {
        Cpanel::Debug::log_warn("Failed to load user file for '$user': $!");
        return;
    }

    my $path = "$Cpanel::Config::CpUser::cpuser_dir/$user";

    return bless {
        user      => $user,
        data      => $data,
        path      => $path,
        _file     => $file,
        _lock     => $lock,
        _pid      => $$,
        is_locked => $is_locked,
    };
}

=head2 $self = I<OBJ>->set_worker_node( $TYPE, $WORKER_ALIAS, $TOKEN )

Stores the given $WORKER_ALIAS and $TOKEN as the user’s worker node
for type $TYPE.

Use this, for example, to configure the user to offload C<mail> ($TYPE)
functionality to C<mailnode1> ($WORKER_ALIAS). See L<Cpanel::API::Tokens>
for logic to create and manage tokens.

Note that you have to C<save()> this change for it to take effect.

=cut

sub set_worker_node {
    my ( $self, $worker_type, $worker_alias, $token ) = @_;

    require Cpanel::LinkedNode::Worker::Storage;
    Cpanel::LinkedNode::Worker::Storage::set( $self->{'data'}, $worker_type, $worker_alias, $token );

    return $self;
}

=head2 $host_token_ar = I<OBJ>->unset_worker_node( $TYPE )

Removes the given worker node $TYPE’s configuration and returns it in
a 2-member array reference ( [ $worker_alias, $token ] ), or undef if
there was no such worker node defined.

Note that you have to C<save()> this change for it to take effect.

=cut

sub unset_worker_node {
    my ( $self, $worker_type ) = @_;

    require Cpanel::LinkedNode::Worker::Storage;
    return Cpanel::LinkedNode::Worker::Storage::unset( $self->{'data'}, $worker_type );
}

sub save {
    my ($self) = @_;

    my $user = $self->{'user'};
    my $data = $self->{'data'};

    if ( $self->{'_pid'} != $$ ) {
        Cpanel::Debug::log_die('Locked in parent, cannot save');
        return;
    }

    # $data should be some form of hashref, either plain or blessed.
    if ( !UNIVERSAL::isa( $data, 'HASH' ) ) {
        Cpanel::Debug::log_die( __PACKAGE__ . ': hash reference required' );
        return;
    }

    my $clean_data = Cpanel::Config::CpUser::clean_cpuser_hash( $self->{'data'}, $user );
    if ( !$clean_data ) {
        Cpanel::Debug::log_warn("Data for user '$user' was not saved.");
        return;
    }

    if ( !$self->{'_file'} || !$self->{'_lock'} ) {
        Cpanel::Debug::log_warn("Unable to save user file for '$user': file not open and locked for writing");
        return;
    }

    require Cpanel::SafeFile::Replace;

    require Cpanel::Autodie;

    my $newfh = Cpanel::SafeFile::Replace::locked_atomic_replace_contents(
        $self->{'_file'}, $self->{'_lock'},

        sub {
            my ($fh) = @_;

            chmod( 0640, $fh ) or do {
                warn sprintf( "Failed to set permissions on “%s” to 0%o: %s", $self->{'path'}, 0640, $! );
            };

            return Cpanel::Autodie::syswrite_sigguard(
                $fh,
                Cpanel::Config::CpUser::Write::serialize($clean_data),
            );
        }

      )
      or do {
        Cpanel::Debug::log_warn("Failed to save user file for “$user”: $!");
      };

    $self->{'_file'} = $newfh;

    # Calculate user GID
    my $cpgid = Cpanel::Config::CpUser::get_cpgid($user);

    # Set the group ownership of the file
    if ($cpgid) {
        chown 0, $cpgid, $self->{'path'} or do {
            Cpanel::Debug::log_warn("Failed to chown( 0, $cpgid, $self->{'path'}): $!");
        };
    }

    if ( $INC{'Cpanel/Locale/Utils/User.pm'} ) {
        Cpanel::Locale::Utils::User::clear_user_cache($user);
    }

    # Recache updated file
    Cpanel::Config::CpUser::recache( $data, $user, $cpgid );

    require Cpanel::SafeFile;
    Cpanel::SafeFile::safeclose( $self->{'_file'}, $self->{'_lock'} ) or do {
        Cpanel::Debug::log_warn("Failed to safeclose $self->{'path'}: $!");
    };

    $self->{'_file'}     = $self->{'_lock'} = undef;
    $self->{'is_locked'} = 0;

    return 1;
}

sub abort {
    my ($self) = @_;

    my $user = $self->{'user'};
    my $data = $self->{'data'};

    if ( $self->{'_pid'} != $$ ) {
        Cpanel::Debug::log_die('Locked in parent, cannot save');
        return;
    }

    require Cpanel::SafeFile;
    Cpanel::SafeFile::safeclose( $self->{'_file'}, $self->{'_lock'} );
    $self->{'_file'}     = $self->{'_lock'} = undef;
    $self->{'is_locked'} = 0;

    return 1;
}

sub DESTROY {
    my ($self) = @_;

    return unless $self->{'is_locked'};
    return if Cpanel::Destruct::in_dangerous_global_destruction();
    return unless $self->{'_pid'} == $$;

    Cpanel::SafeFile::safeclose( $self->{'_file'}, $self->{'_lock'} );

    # Should not be needed, but I saw what looked like a double DESTROY call.
    $self->{'is_locked'} = 0;
    return;
}

1;
