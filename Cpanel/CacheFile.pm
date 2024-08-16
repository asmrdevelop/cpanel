package Cpanel::CacheFile;

# cpanel - Cpanel/CacheFile.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf8

=head1 NAME

Cpanel::CacheFile - Base class for on-disk caches

=head1 SYNOPSYS

    package MyCache;

    use parent qw( Cpanel::CacheFile );

    sub _PATH {
        my ($class, $user) = @_;
        return "/path/to/$user/file";
    }

    sub _TTL { return 300 }                 #seconds, i.e., 5 minutes

    sub _MODE { return 0644 }               #defaults to 0600

    sub _OWNER { return 'root', 'nobody' }  #defaults to root

    sub _INVALIDATE { return shouldInvalidate() ? 1 : 0 }

    package MyCacheWithLoader

    use parent qw( MyCache );

    sub _LOAD_FRESH { return load_fresh_data() }

    package main;

    use MyCache;
    use MyCacheWithLoader;

    local $@;

    my $data;
    eval { $data = MyCache->load('theuser'); 1 } or do {
        die if !UNIVERSAL::isa( $@, 'Cpanel::CacheFile::NEED_FRESH' );
        $data = load_new_data();
        warn if !eval { MyCache->save($data, 'theuser'); 1 };
    };

    my $data2 = MyCacheWithLoader->load();

    MyCache->delete($user);

=head1 NOTES

The SYNOPSIS above should give you a good idea of how to use this.
Notes below:

=over 4

=item * load() and save() accept arbitrary arguments that they pass on to
C<_PATH()>, C<_TTL()>, C<_MODE()>, C<_OWNER()>, and C<_LOAD_FRESH()>.
What those methods do with the
arguments is up to them. This facilitates, for example, per-user storage.
It probably shouldn’t be used for much else .. ?

=item * The base C<_LOAD_FRESH()> method throws a special exception of type
C<Cpanel::CacheFile::NEED_FRESH>. It’s best if you can override this method,
but if not, B<you must always catch the exception and check for it,>
since that is your indicator to load fresh data.

=item * If C<_LOAD_FRESH()> is overridden and returns a data structure,
the base class will try to save it, warn()ing on failure if we are root
or if the error was a file access denial.

=item * If C<_INVALIDATE> is defined by a child class, it will forcibly
invalidate the cache when the method returns true.

=back

It would seem most useful to override C<_LOAD_FRESH()> when access to the
“fresh” data is not privileged information.

=cut

use Try::Tiny;

use Cpanel::Debug                ();
use Cpanel::AdminBin::Serializer ();
use Cpanel::Autodie              ();
use Cpanel::FileUtils::Write     ();
use Cpanel::PwCache              ();

use constant {
    _ENOENT => 2,
    _EACCES => 13,
    _MODE   => 0600,
};

use constant _OWNER => ();

#----------------------------------------------------------------------
# Subclass interface

sub _PATH { ... }    ## no critic qw(ControlStructures::ProhibitYadaOperator)

sub _TTL { ... }     ## no critic qw(ControlStructures::ProhibitYadaOperator)

sub _LOAD_FRESH {
    my ($self) = @_;
    die Cpanel::CacheFile::NEED_FRESH->new();
}

sub _LOAD_FROM_FH {
    return Cpanel::AdminBin::Serializer::LoadFile( $_[1] );
}

sub _DUMP {
    return Cpanel::AdminBin::Serializer::Dump( $_[1] );
}

#----------------------------------------------------------------------

my $CHUNK = 1 << 17;    #supposedly (?) most efficient size

sub save {
    my ( $self, $new_data, @args ) = @_;

    my $path = $self->_PATH(@args);

    my @user_group = $self->_OWNER(@args);

    # Considered changing this to write the file as _OWNER(), but
    # that doesn’t work because _OWNER() may not have write privileges
    # on the parent directory. So we chown() before installation.
    Cpanel::FileUtils::Write::overwrite(
        $path,
        $self->_DUMP($new_data),
        {
            before_installation => sub ($fh) {
                Cpanel::Autodie::chmod( $self->_MODE(@args), $fh );

                if ( @user_group && !$> ) {
                    $self->_chown( $fh, @user_group );
                }
            },
        },
    );

    return 1;
}

sub delete {
    my ( $self, @args ) = @_;

    return Cpanel::Autodie::unlink_if_exists( $self->_PATH(@args) );
}

#This reduced privileges for reading.
#
#We want to reduce privileges for open() if:
#   - We’re running as root
#   - _OWNER() returns a non-root user
#
sub _reduced_privs_obj {
    my ( $self, @args ) = @_;

    my ($user) = $self->_OWNER(@args);

    if ( length($user) && $user ne 'root' && !$> ) {
        require Cpanel::AccessIds::ReducedPrivileges;
        return Cpanel::AccessIds::ReducedPrivileges->new($user);
    }

    return undef;
}

sub load {
    my ( $self, @args ) = @_;

    my $path = $self->_PATH(@args);

    my $rfh;
    my $need_fresh;

    {
        my $privs_obj = $self->_reduced_privs_obj(@args);

        local $!;
        open( $rfh, '<', $path ) or do {
            if ( $! != _ENOENT() && $! != _EACCES() ) {
                warn "open(< $path) as EUID $>: $!";
            }

            $need_fresh = 1;
        };

        if ( !$need_fresh ) {
            require Cpanel::HiRes;
            my $age = Cpanel::HiRes::time() - ( Cpanel::HiRes::fstat($rfh) )[9];

            $need_fresh = ( $age > $self->_TTL(@args) ) ? 1 : 0;

            if ( $age < 0 ) {

                #Log this rather than warn()ing since it tends to happen
                #with some frequency and is recoverable anyway. It’s really
                #only a concern if it happens a LOT, which we can’t easily detect.
                Cpanel::Debug::log_warn( sprintf "“Time warp”: “%s” is %0.2f seconds old!", $path, $age );

                $need_fresh = 1;
            }
        }

        #Allow child classes to define custom invalidation conditions if they so desire
        $need_fresh //= $self->_INVALIDATE($path) if $self->can('_INVALIDATE');

        my $loaded;

        if ( !$need_fresh ) {
            local $@;    #GetMX loads 1000s of these so we avoid Try::Tiny
            eval { $loaded = $self->_LOAD_FROM_FH($rfh); };
            if ($@) {
                warn;
                $need_fresh = 1;
            }

            return $loaded if !$need_fresh;
        }
    }

    #NOTE: Unless the subclass has overridden this class’s _LOAD_FRESH(),
    #the following will die().
    my $fresh = $self->_LOAD_FRESH(@args);

    try {
        $self->save( $fresh, @args );
    }
    catch {

        #Don’t warn if the error is just that we don’t have
        #write access to the file.
        if ( !$> || !try { $_->error_name() eq 'EACCES' } ) {
            local $@ = $_;
            warn;
        }
    };

    return $fresh;
}

# TODO: Refactor this private to a public interface. It’s used in
# at least one subclass already.
sub _chown {
    my ( $self, $path_or_fh, @user_group ) = @_;

    if (@user_group) {
        my ( $user, $group ) = @user_group;

        if ( length $user ) {
            $user = ( Cpanel::PwCache::getpwnam_noshadow($user) )[2];
        }
        else {
            $user = -1;
        }

        if ( length $group ) {
            $group = ( getgrnam $group )[2];
        }
        else {
            $group = -1;
        }

        Cpanel::Autodie::chown( $user, $group, $path_or_fh );
    }

    return;
}

package Cpanel::CacheFile::NEED_FRESH;

sub new {
    my ($class) = @_;
    return bless [], $class;
}

1;
