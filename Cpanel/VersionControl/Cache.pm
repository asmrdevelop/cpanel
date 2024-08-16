package Cpanel::VersionControl::Cache;

# cpanel - Cpanel/VersionControl/Cache.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=head1 NAME

Cpanel::VersionControl::Cache

=head1 SYNOPSIS

    use Cpanel::VersionControl::Cache ();

    my $foo = Cpanel::VersionControl::Cache::retrieve('/home/user/foo');

    my $vc = Cpanel::VersionControl->new(...);
    Cpanel::VersionControl::Cache::update($vc);

    Cpanel::VersionControl::Cache::remove('/home/user/foo');

=head1 DESCRIPTION

Cpanel::VersionControl::Cache is a file-backed cache of
Cpanel::VersionControl objects.  It operates as a JSON file, and can
serialize and deserialize as needed.

=cut

use strict;
use warnings;

use Cpanel::Exception               ();
use Cpanel::LoadModule              ();
use Cpanel::PwCache                 ();
use Cpanel::Transaction::File::JSON ();

use Exporter;
our @EXPORT_OK = qw{update retrieve remove};

=head1 VARIABLES

=cut

=head2 $VC_DATA_FILE

$Cpanel::VersionControl::VC_DATA_FILE stores cached information of
repositories under version control.

=cut

our $VC_DATA_FILE = '/.cpanel/datastore/vc_list_store';

my $logger;

=head1 FUNCTIONS

=head2 Cpanel::VersionControl::Cache::update()

Add an object or objects to the cached repository information.

=head3 Arguments

The single argument is an object or arrayref of repository objects, and
is required.

=head3 Returns

Nothing.  Completion implies success.

=head3 Dies

If the transaction fails for any reason, a Cpanel::Exception is thrown.

=cut

sub update {
    my ($repo) = @_;

    my $transaction = _lock_cache();

    my $cache = _load_cache($transaction);

    $repo = [$repo] if ref $repo ne 'ARRAY';
    for my $obj (@$repo) {
        $cache = [ grep { $_->{'repository_root'} ne $obj->{'repository_root'} } @$cache ];
        push @$cache, $obj;
    }

    _save_cache( $transaction, $cache );
    _unlock_cache($transaction);

    return;
}

=head2 Cpanel::VersionControl::Cache::retrieve()

Read cached information for existing version control repositories

=head3 Arguments

A repository root may be specified, but is optional.

=head3 Returns

An arrayref of the objects contained in the cache file, or if a
repository root was provided as an argument, the object for that
repository.

=head3 Dies

If the transaction with the cache file fails for any reason, a
Cpanel::Exception will result.

=head3 Notes

If there is no data file, this function will not create one.

=cut

sub retrieve {
    my ($repo_root) = @_;

    my $cache = _load_cache();

    if ($repo_root) {
        return ( grep { $_->{'repository_root'} eq $repo_root && $_ } @$cache )[0];
    }
    return $cache;
}

=head2 Cpanel::VersionControl::Cache::remove()

Remove an entry from the cache.

=head3 Arguments

A repository root of an object which we wish to remove.

=cut

sub remove {
    my ($repo_root) = @_;

    my $transaction = _lock_cache();

    my $cache = _load_cache($transaction);

    $cache = [ grep { $_->{'repository_root'} ne $repo_root && $_ } @$cache ];

    # If we've no longer got anything in the list, we'll just remove
    # the cache file entirely, and let the 'no file' logic take over.
    if ( scalar @$cache ) {
        _save_cache( $transaction, $cache );
        _unlock_cache($transaction);
    }
    else {
        _unlock_cache($transaction);
        my $homedir = Cpanel::PwCache::gethomedir();
        unlink $homedir . $VC_DATA_FILE;
    }

    return;
}

=head2 Cpanel::VersionControl::Cache::repo_exists()

Tells if a directory is already in the list of repository roots.

=head3 Arguments

A repository path.

=head3 Returns

1 if there is an object for the repository_root, 0 if there is not.

=cut

sub repo_exists {
    my ($repo_root) = @_;

    return 0 unless $repo_root;

    my $cache = _load_cache();

    return ( grep { $_->{repository_root} && $_->{repository_root} eq $repo_root } @$cache ) ? 1 : 0;
}

=head1 PRIVATE FUNCTIONS

=head2 Cpanel::VersionControl::Cache::_lock_cache()

Begins a transaction with the cache file.

=head3 Returns

A transaction object, which has a lock on the cache file.

=head3 Dies

If the transaction cannot be started, a Cpanel::Exception will be thrown.

=head3 Notes

There's already a lock() function in perl, so we can't just call this lock.

=cut

sub _lock_cache {
    my $homedir = Cpanel::PwCache::gethomedir();

    my $trans;

    eval { $trans = Cpanel::Transaction::File::JSON->new( 'path' => $homedir . $VC_DATA_FILE ); };
    if ($@) {
        _logger()->warn( Cpanel::Exception::get_string($@) );
        die $@;
    }
    return $trans;
}

=head2 Cpanel::VersionControl::Cache::_read_tagged_format()

If the cache file is written in the old tagged format, we need to be
able to read it in so that we can convert it into our new format.
Fortunately, we can parse things out with some fairly simple regular
expressions.

=head3 Arguments

=over 4

=item $path

The path of the cache file to load.

=back

=cut

sub _read_tagged_format {
    my ($path) = @_;
    open my $fh, '<', $path or die $!;
    my $contents = <$fh>;
    close $fh;
    $contents =~ s/^\[//;
    $contents =~ s/]$//;
    Cpanel::LoadModule::load_perl_module('JSON::XS');
    my @objs;

    for my $repo ( split /(?<=}]),(?=\()/, $contents ) {
        $repo =~ m/^\("([^"]+)"\)\[(.*)\]$/;
        my $type = $1;
        my $json = $2;
        my $obj;
        eval { $obj = JSON::XS::decode_json($json); };
        if ($@) {
            _logger()->warn($@);
            die $@;
        }
        $obj->{'type'} = $type;
        push @objs, $obj;
    }
    return \@objs;
}

=head2 Cpanel::VersionControl::Cache::_unlock_cache()

Ends a transaction with the cache file.

=head3 Arguments

=over 4

=item $transaction

A transaction object that was returned from _lock_cache().

=back

=head3 Returns

Nothing.

=head3 Dies

If the transaction can not be closed out, a Cpanel::Exception will result.

=cut

sub _unlock_cache {
    my ($transaction) = @_;

    $transaction->close_or_die();

    return;
}

=head2 Cpanel::VersionControl::Cache::_load_cache()

Loads the file data into the memory cache.

=head3 Arguments

An optional transaction object may be passed in.  If not, the function
will handle its own locking.

=head3 Returns

Nothing.

=head3 Dies

If there is a problem with the locking, a Cpanel::Exception will result.

=cut

sub _load_cache {
    my ($transaction) = @_;

    my $path = Cpanel::PwCache::gethomedir() . $VC_DATA_FILE;

    my $cache = [];

    if ( -e $path && -s _ ) {
        my $need_to_lock = !defined $transaction;
        $transaction = _lock_cache() if $need_to_lock;

        my $need_to_save = 0;
        eval { $cache = $transaction->get_data(); };

        # this is here to handle legacy tagged format
        if ($@) {
            $need_to_save = 1;
            $cache        = _read_tagged_format($path);
        }

        # The transaction object returns a scalar reference to 'undef' if
        # there is nothing to read.
        if ( ref $cache eq 'SCALAR' ) {
            $cache = [];
        }
        else {
            $cache = [
                map {
                    my $obj = $_;
                    Cpanel::LoadModule::load_perl_module( $obj->{'type'} );
                    $obj->{'type'}->deserialize($obj);
                  }
                  grep { $_->{'type'} =~ m/^Cpanel::VersionControl::/ and $_ } @$cache
            ];
        }

        _save_cache( $transaction, $cache ) if $need_to_save;
        _unlock_cache($transaction)         if $need_to_lock;
    }

    return $cache;
}

=head2 Cpanel::VersionControl::Cache::_save_cache()

Given a transaction object and an arrayref of objects, write out the
data in the appropriate format.

=head3 Arguments

=over 4

=item $transaction

The transaction object which was returned from _lock_cache()

=item $data

An arrayref of objects to write.

=back

=cut

sub _save_cache {
    my ( $trans, $data ) = @_;

    my @objs = map {
        my $obj = $_->serialize();
        $obj->{'type'} = ref $_;
        $obj;
    } grep { ( ref $_ ) =~ m/^Cpanel::VersionControl::/ and $_ } @$data;
    $trans->set_data( \@objs );
    $trans->save_or_die();
    return;
}

sub _logger {
    return $logger ||= do {
        Cpanel::LoadModule::load_perl_module('Cpanel::Logger');
        Cpanel::Logger->new();
    };
}

=head1 CONFIGURATION AND ENVIRONMENT

Each user of the Cpanel::VersionControl system will have a cache file
in their home directory in the location described by
$Cpanel::VersionControl::Cache::VC_DATA_FILE.  This module maintains
the contents of that file.

There are no environment variables which are used by this module.

=head1 DEPENDENCIES

L<Cpanel::LoadModule>, L<Cpanel::PwCache>,
L<Cpanel::Transaction::File::JSON>, and L<Cpanel::VersionControl>.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2017, cPanel, Inc.  All rights reserved.  This code is
subject to the cPanel license.  Unauthorized copying is prohibited.

=cut

1;
