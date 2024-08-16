package Cpanel::Transaction::File::Base;

# cpanel - Cpanel/Transaction/File/Base.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
#NOTE: Use this class for read/write operations ONLY.
#If you only need to read, then use BaseReader.
#
#TODO: Convert this to throw exceptions rather than two-part return.
#----------------------------------------------------------------------

use strict;
use warnings;

use parent 'Cpanel::Transaction::File::BaseReader';

use Cpanel::Autodie           ();
use Cpanel::Destruct          ();
use Cpanel::Exception         ();
use Cpanel::Fcntl::Constants  ();
use Cpanel::Finally           ();
use Cpanel::OrDie             ();
use Cpanel::SafeFile          ();
use Cpanel::SafeFile::Replace ();
use Cpanel::Signal::Defer     ();

use constant {
    _EACCES => 13,
    _ENOENT => 2,
};

my $PACKAGE = __PACKAGE__;

my $MINIMUM_PERMISSIONS = 0600;

my $MINIMUM_LOCK_WAITTIME = 30;

# The amount of time to wait before safefile is allowed
# to clobber a lock because we assume something is deadlocked
our $DEFAULT_TRANSACTION_LOCK_WAIT_TIME = 300;

#opts are:
#   path - required (duh!)
#
#   restore_original_permissions - boolean; if passsed, this will ensure that
#       the file after the transaction has the same mode and ownership as
#       before. You probably always want this unless you pass explicit
#       “permissions” and “ownership” arguments.
#
#   permissions - minimum is 0600 (which is the default)
#
#   lock_waittime - The number of seconds to wait before clobbering the lock (defaults to DEFAULT_TRANSACTION_LOCK_WAIT_TIME)
#
#   sysopen_flags - a BIT FIELD composed of bit-or’d Fcntl values.
#       If undef, defaults to O_CREAT. Note that O_RDWR is always passed.
#
#   ownership - optional arrayref of:
#       user or UID
#       group or GID (optional; defaults to user's group)
#
sub new {
    my ( $class, %opts ) = @_;

    if ( $class eq $PACKAGE ) {
        die "Do not instantiate $PACKAGE directly. Instantiate a subclass instead.";
    }

    #Implementor error
    die "No file!" if !length $opts{'path'};

    #Ensure 0600 as minimum permissions;
    #e.g., if 0444 is passed in, use 0644.
    my $permissions   = $opts{'permissions'}   || 0600;
    my $lock_waittime = $opts{'lock_waittime'} || $DEFAULT_TRANSACTION_LOCK_WAIT_TIME;

    #Programmer error; lock_waittime must be sane
    die sprintf( 'lock_waittime must be >= 30', $MINIMUM_LOCK_WAITTIME ) if $lock_waittime < $MINIMUM_LOCK_WAITTIME;

    my $original_permissions         = $permissions;
    my $restore_original_permissions = 0;

    my $sysopen_flags         = $opts{'sysopen_flags'} // $Cpanel::Fcntl::Constants::O_CREAT;
    my $create_file_if_needed = $sysopen_flags & $Cpanel::Fcntl::Constants::O_CREAT;

    my @_self_attributes;

    #If $create_file_if_needed, then we have to pre-stat() the file;
    #otherwise, let’s wait to stat() the opened filehandle.
    my $set_originals_cr = sub {
        my ($thing_to_stat) = @_;

        my ( $mode, $uid, $gid ) = ( stat $thing_to_stat )[ 2, 4, 5 ];
        if ( length $mode ) {
            $original_permissions         = $mode & 07777;
            $restore_original_permissions = 1;
            push @_self_attributes, (
                _original_mode      => $original_permissions,
                _original_ownership => [ $uid, $gid ],
            );
        }
        elsif ( $! != _ENOENT() ) {
            warn "stat($thing_to_stat): $!";
        }
        return;
    };

    if ($create_file_if_needed) {
        $set_originals_cr->( $opts{'path'} ) if $opts{'restore_original_permissions'};
    }

    my ( $lock, $lock_err, $fh );
    {
        #NOTE: This will not alter permissions for a file that already exists.
        #Since we just changed the permissions above, though, that doesn't matter.
        local $!;
        local $Cpanel::SafeFile::LOCK_WAIT_TIME = $lock_waittime;

        # This accomodates .htaccess files created the by wordpress
        # Ithemes plugin which sadly sets the permissions to 0444
        #
        # We do not want to throw a warrning here because this is
        # the norm even if we do not like it.
        $lock = Cpanel::SafeFile::safesysopen_no_warn_on_fail(
            $fh,
            $opts{'path'},
            $Cpanel::Fcntl::Constants::O_RDWR | $sysopen_flags,
            $permissions,
        );
        $lock_err = $!;

        if ( $lock_err == _EACCES() ) {

            # case CPANEL-9289:
            # The permissions may be missing the write bit so
            # try again with fixing the permissions first
            if ( sysopen( $fh, $opts{'path'}, $Cpanel::Fcntl::Constants::O_RDONLY ) ) {
                _set_permissions( $fh, $permissions, $opts{'ownership'} );
                close($fh);

                $lock = Cpanel::SafeFile::safesysopen(
                    $fh,
                    $opts{'path'},
                    $Cpanel::Fcntl::Constants::O_RDWR | $sysopen_flags,
                    $permissions,
                );
                $lock_err = $!;
            }
        }
        elsif ( ( $lock_err == _ENOENT ) && !$create_file_if_needed ) {

            #The caller requested that we *not* create the file if it
            #doesn’t exist, which means we should return rather than die().
            return undef;
        }
    }

    if ( !$lock || !$fh || !ref $lock ) {
        require Cpanel::FileUtils::Attr;
        my $attributes = Cpanel::FileUtils::Attr::get_file_or_fh_attributes( $opts{'path'} );

        if ($lock_err) {
            die Cpanel::Exception::create( 'IO::FileLockError', [ 'path' => $opts{'path'}, 'error' => $lock_err, immutable => $attributes->{'IMMUTABLE'}, 'append_only' => $attributes->{'APPEND_ONLY'} ] );
        }
        else {
            require Cpanel::Locale;
            my $locale = Cpanel::Locale->get_handle();
            die Cpanel::Exception::create( 'IO::FileLockError', [ 'path' => $opts{'path'}, error => $locale->maketext("An unknown permissions, quota, or disk error occurred."), immutable => $attributes->{'IMMUTABLE'}, 'append_only' => $attributes->{'APPEND_ONLY'} ] );
        }
    }

    if ( !$create_file_if_needed ) {
        $set_originals_cr->($fh) if $opts{'restore_original_permissions'};
    }

    _set_permissions( $fh, $restore_original_permissions ? $original_permissions : $permissions, $opts{'ownership'} );

    return bless {
        @_self_attributes,
        _path                         => $opts{'path'},
        _original_pid                 => $$,
        _original_euid                => $>,
        _fh                           => $fh,
        _lock                         => $lock,
        _ownership                    => $opts{'ownership'},
        _restore_original_permissions => $restore_original_permissions,
        _permissions                  => $permissions,
        _original_permissions         => $original_permissions,
        _opts                         => \%opts,
        _did_init_data                => 0,
        _data                         => undef,
    }, $class;
}

sub _set_permissions {
    my ( $fh, $permissions, $ownership, $current_permissions ) = @_;
    if ($ownership) {
        die if 'ARRAY' ne ref $ownership;
        require Cpanel::FileUtils::Access;
        return Cpanel::FileUtils::Access::ensure_mode_and_owner(
            $fh,
            $permissions,
            @$ownership,
        );
    }
    $current_permissions //= ( ( stat $fh )[2] & 07777 );
    return if $current_permissions == $permissions;
    return Cpanel::Autodie::chmod( $permissions, $fh );
}

#NOTE: Is this necessary? It duplicates BaseReader.pm's stub method.
sub _init_data {
    die "Do not instantiate $PACKAGE directly; use a subclass instead.";
}

sub set_data {
    my ( $self, $new_data ) = @_;

    die 'Must be a reference!' if !ref $new_data;

    $self->{'_data'} = $new_data;

    $self->{'_did_init_data'} = 1;

    return;
}

sub get_path {
    my ($self) = @_;

    return $self->{'_path'};
}

#For convenience, since this is such common behavior. It combines the
#saving and closing operations into a single call and will (normally)
#always attempt both, even if the save operation fails. (See below for
#how to prevent that.)
#
#%opts is:
#   do_between - coderef (see below)
#
#'do_between' is an optional coderef to execute between saving and closing.
#This is useful if, for example, you need to sync an external data store
#to this transaction after saving but before closing.
#
#If save() succeeds, then we:
#   1) call do_between->(undef)
#   2) call close_or_die(); any error gets thrown.
#
#If save() fails, then we:
#   1) call do_between->($save_err)     #$save_err isa Cpanel::Exception
#   2) call close_or_die()
#       - If close_or die() fails, then the exceptions are assembled
#         into a Cpanel::Exception::Collection object, which is thrown.
#
#..i.e., 'do_between' receives the error from the save as a parameter.
#
#If you need to prevent the close in response to a save error, then you
#can simply die() out of the 'do_between' function, e.g.: "die $_[0] if $_[0]"
#
#NOTE: 'do_between'’s return value is thrown away; you'll need to
#shoot back anything interesting from 'do_between' in some other way.
#
sub save_and_close_or_die {
    my ( $self, %opts ) = @_;

    my $save_err;

    local $@;
    eval { $self->save_or_die(%opts); };
    $save_err = $@ if $@;

    if ( $opts{'do_between'} ) {
        $opts{'do_between'}->($save_err);
    }

    eval { $self->close_or_die(%opts); };

    if ($@) {
        if ( defined $save_err ) {
            die Cpanel::Exception::create( 'Collection', [ exceptions => [ $save_err, $@ ] ] );
        }
        die;
    }

    if ($save_err) {
        local $@ = $save_err;
        die;
    }

    return 1;
}

#Same function as save_and_close_or_die(), except:
#   - It returns two-part.
#   - It gives the two-part return of save() to the “do_between” function.
#
#Since there can be failures from both save() and close(), this will
#concatenate any failures from them together with a single space.
#
sub save_and_close {
    my ( $self, @opts ) = @_;

    return $self->_convert_die_to_two_part_return( 'save_and_close_or_die', @opts );
}

#LEGACY. Prefer save_or_die(), or save_and_close_or_die(), instead.
#
sub save {
    my ( $self, @opts ) = @_;

    return $self->_convert_die_to_two_part_return( 'save_or_die', @opts );
}

#LEGACY. Prefer close_or_die(), or save_and_close_or_die(), instead.
#
sub close {
    my ( $self, @opts ) = @_;

    return $self->_convert_die_to_two_part_return( 'close_or_die', @opts );
}

# Suppress warns for updatenow.static.
{
    no warnings 'once';
    *abort = \&close;
}

sub _convert_die_to_two_part_return {
    my ( $self, $method, @opts ) = @_;

    return Cpanel::OrDie::convert_die_to_multi_return(
        sub {
            return scalar $self->$method(@opts);
        }
    );
}

#opts:
#   offset => cf. Raw.pm subclass
#
#   minimum_mtime => If passed, and the saved file’s mtime is less,
#       then the new mtime will be set to this value. See
#       Cpanel::ZoneFile::Transaction for how/why this can be useful.
#
#   mtime => If passed then the new mtime will be set to this value. See
#       Cpanel::Config::userdata::UpdateCache for how/why this can be useful.
#
#   write_cr => coderef to do the write.
#       It gets $self and the offset as arguments.
#       It should return 1 on success, 0 on failure (and set $!)
#   validate_cr => coderef to validate the new file before it is committed.
#       It gets $self and the temporary filename as arguments.
#       It should return 1 on success, 0 on failure.
sub _save_or_die {
    my ( $self, %OPTS ) = @_;

    my $fh = $self->{'_fh'};

    my $offset = $OPTS{'offset'} || 0;

    # If we write an offset we have to work on the file
    # and cannot do a rename() in place.  This is a
    # "non durable write" because if the system or the process crashes
    # the file will be left in an indetermine state.
    my $use_non_durable_writes = $offset && !defined $OPTS{'validate_cr'};

    if ($use_non_durable_writes) {
        if ( tell($fh) != $offset ) {
            Cpanel::Autodie::seek( $fh, $offset, 0 );
        }
    }

    my $finally;
    if ( !$OPTS{'signals_already_deferred'} && $use_non_durable_writes ) {
        $self->{'_defer'} ||= Cpanel::Signal::Defer->new(
            defer => {
                signals => Cpanel::Signal::Defer::NORMALLY_DEFERRED_SIGNALS(),
                context => "writing “$self->{'_path'}” to disk",
            }
        );

        $finally = Cpanel::Finally->new(
            sub {
                $self->_reset_deferred_signals();
            }
        );
    }

    my $ret;
    if ($use_non_durable_writes) {
        $ret = $OPTS{'write_cr'}->( $self, $offset );

        Cpanel::Autodie::truncate( $fh, tell $fh );

    }
    else {
        die Cpanel::Exception::create_raw( 'IOError', 'File handle not open' ) if !fileno $fh;

        # In v56 we changed the transaction object to create
        # create a new file and rename it in place via
        # Cpanel::SafeFile::Replace::locked_atomic_replace_contents in
        # order to provide additional durability in the transaction
        # in the event the filesystem or system crashes during the
        # write.

        $self->{'_fh'} = Cpanel::SafeFile::Replace::locked_atomic_replace_contents(
            $fh,
            $self->{'_lock'},
            sub {
                my ( $temp_fh, $temp_file, $temp_file_permissions ) = @_;
                local $self->{'_fh'} = $temp_fh;    # This is localized to avoid corrupting the _fh setting during errors.

                # _ownership is the constructor’s “permissions” argument.
                #
                # _original_ownership is only set if the constructor
                #   received the “restore_original_permissions” flag.
                #
                _set_permissions( $self->{'_fh'}, $self->{'_permissions'}, $self->{'_ownership'} || $self->{'_original_ownership'}, $temp_file_permissions );

                $ret = $OPTS{'write_cr'}->( $self, 0 );

                if ( $OPTS{'mtime'} ) {
                    utime( ( $OPTS{'mtime'} ) x 2, $self->{'_fh'} ) or die "Failed to set utime of “$self->{'_path'}” to “$OPTS{'mtime'}”: $!";
                }
                elsif ( $OPTS{'minimum_mtime'} && $self->get_mtime() < $OPTS{'minimum_mtime'} ) {
                    utime( ( $OPTS{'minimum_mtime'} ) x 2, $self->{'_fh'} ) or die "Failed to set utime of “$self->{'_path'}” to “$OPTS{'minimum_mtime'}”: $!";
                }
                $ret &&= $OPTS{'validate_cr'}->($temp_file) if defined $OPTS{'validate_cr'};
                return $ret;
            }
        );
    }

    if ( $self->{'_restore_original_permissions'} ) {
        _set_permissions( $self->{'_fh'}, $self->{'_original_permissions'} );
    }

    undef $finally;

    return $ret;
}

#NOTE: Subsequent calls to this will not produce an exception.
#
sub close_or_die {
    my ($self) = @_;

    if ( $self->{'_fh'} ) {
        Cpanel::SafeFile::safeclose( $self->{'_fh'}, $self->{'_lock'} ) or do {
            die Cpanel::Exception->create( 'The system failed to release the lock on the file “[_1]” because of an error: [_2]', [ $self->{'_path'}, $! ] );
        };

        @{$self}{qw( _path _fh _lock )} = ();
    }

    return 1;
}

sub _reset_deferred_signals {
    my ($self) = @_;

    if ( $self->{'_defer'} ) {
        my $defer_obj           = delete $self->{'_defer'};
        my $deferred_signals_ar = $defer_obj->get_deferred();
        $defer_obj->restore_original_signal_handlers();

        if ( grep { $_ eq 'ALRM' } @$deferred_signals_ar ) {
            kill( 'ALRM', $$ );
        }
    }

    return;
}

sub DESTROY {
    my ($self) = @_;

    return if !$self->{'_fh'};    # nothing to do

    return if Cpanel::Destruct::in_dangerous_global_destruction();

    return if $$ != $self->{'_original_pid'};

    if ( $> != $self->{'_original_euid'} ) {
        warn "Unlocking “$self->{'_path'}” as EUID $> after it was locked as EUID $self->{'_original_euid'}!\n";
    }

    # In case this runs at global destruction, we trap the error.
    local $@;
    warn if !eval { $self->close_or_die() };

    return;
}

1;
