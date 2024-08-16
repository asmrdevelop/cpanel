package Cpanel::Domain::TLS::Write;

# cpanel - Cpanel/Domain/TLS/Write.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::Domain::TLS::Write - Write to the domain-level TLS datastore.

=head2 DESCRIPTION

    #Prepare the directory. This should only need to be run once,
    #though it will also refresh permissions on an already-created
    #directory.
    Cpanel::Domain::TLS::Write->init();

    #Returns 1 or 0 to indicate removal or no-op.
    my $removed = Cpanel::Domain::TLS::Write->enqueue_unset_tls($domain);

    #Process queue items that are at least MIN_AGE_TO_UNSET seconds old.
    Cpanel::Domain::TLS::Write->process_unset_tls_queue();

    #Use for untrusted items. This does the following:
    #   - checks for OCSP revocation
    #   - checks key and signature algorithm strength.
    #
    #… then sends the data off to set_tls__no_verify().
    #
    #NOTE: This used to do an OpenSSL verify(), but since that
    #operation is time-consuming and duplicated work that
    #Cpanel::SSLInstall will already have done, it was removed.
    #
    #(The OCSP revocation check is still expensive, FYI.)
    #
    Cpanel::Domain::TLS::Write->set_tls(
        domain => $domain,
        key => $key_pem,
        certificate => $crt_pem,
        cabundle => $cab_pem,   #order-agnostic
    );

    #This does only “basic” validation:
    #   - key/cert match
    #   - domain match,
    #
    #It accepts the same args as set_tls().
    Cpanel::Domain::TLS::Write->set_tls__no_verify( .. );

=head1 DISCUSSION

Only root can run these functions.

=cut

use strict;
use warnings;

use parent qw( Cpanel::Domain::TLS );

use Try::Tiny;

use Cpanel::Autodie          ();
use Cpanel::Crypt::Algorithm ();
use Cpanel::Exception        ();
use Cpanel::Fcntl::Constants ();
use Cpanel::FileUtils::Dir   ();
use Cpanel::FileUtils::Flock ();
use Cpanel::Linux::Constants ();
use Cpanel::PwCache          ();
use Cpanel::WildcardDomain   ();

#Only root should be able to read the directory,
#though anyone should be able to traverse it.
use constant {

    MIN_AGE_TO_UNSET => 2 * 60 * 60,    #2 hours

    _DIR_PERMS => 0711,
    _ENOENT    => 2,
    _EEXIST    => 17,

    _PENDING_DELETE_PATH_FLAGS => $Cpanel::Fcntl::Constants::O_CREAT | $Cpanel::Fcntl::Constants::O_EXCL,
};

=head1 METHODS

=head2 I<CLASS>->init()

Sets up the filesystem for this datastore.

=cut

sub init {
    my ($class) = @_;

    require Cpanel::Mkdir;

    my $dir = $class->BASE_PATH();

    for my $dir ( $class->BASE_PATH(), $class->_pending_delete_dir() ) {
        Cpanel::Mkdir::ensure_directory_existence_and_mode( $dir, _DIR_PERMS );
    }

    return;
}

=head2 $enqueued_yn = I<CLASS>->enqueue_unset_tls( NAME1, NAME2, NAME3, .. )

Enqueues entries for deletion and schedules a cleanup task to do the
actual removal. After this, the functionality
to list datastore entries and to check for existence will return
false for the NAMEs; however, the filesystem entries will still exist
until the cleanup task does its work.

We prefer this over C<unset_tls> for the benefit of servers like
Dovecot, which hard-code
certificate paths in their configuration and thus are vulnerable
to “missing certificate” errors if, e.g., a certificate goes away
while the server is restarting.

Returns the number of entries enqueued for deletion. Nonexistent entries
are ignored (i.e., counted as 0).

If an error happens prior to any changes, that error is thrown as an
exception. If an error happens after changes are already made, though,
that error will be reported via C<warn()> instead.

=cut

#Returns 1 if newly enqueued; 0 if it was already in queue.
sub enqueue_unset_tls {    ## no critic qw(Subroutines::RequireArgUnpacking)
    my $class    = shift;
    my $names_ar = \@_;

    my $count = $class->__enqueue_unset_tls_no_task_queue($names_ar);

    $class->__schedule_cleanup_task() if $count;

    return $count;
}

#called by subclass
sub __schedule_cleanup_task {
    my ($class) = @_;

    require Cpanel::ServerTasks;
    Cpanel::ServerTasks::schedule_task(
        ['SSLCleanupTasks'],
        10 + $class->MIN_AGE_TO_UNSET,
        'unset_tls',
    );

    return;
}

=head2 $deleted_yn = I<CLASS>->process_unset_tls_queue()

Delete all items from the unset queue that are at least MIN_AGE_TO_UNSET
seconds old.

Returns the number of entries deleted.

=cut

sub process_unset_tls_queue {
    my ($class) = @_;

    my $lock = $class->__get_write_lock();

    my $delete_dir   = $class->_pending_delete_dir();
    my $deletions_ar = Cpanel::FileUtils::Dir::get_directory_nodes_if_exists($delete_dir) || [];

    my $min_time_to_unset = time - $class->MIN_AGE_TO_UNSET();
    my @old_enough        = grep { ( stat "$delete_dir/$_" )[9] <= $min_time_to_unset } @$deletions_ar;

    for my $name (@old_enough) {
        $class->_clear_unset_queue_entry($name);
        $class->_unset_tls_in_filesystem($name);
    }

    return 0 + @old_enough;
}

=head2 I<CLASS>->rename( OLDNAME => NEWNAME )

Renames an entry in the datastore. Returns:

=over

=item 0 if no entry named OLDNAME exists

=item 0 if OLDNAME is pending unset

=item 1 if an entry is renamed

=back

=cut

*rename = *_rename_in_filesystem;

=head2 I<CLASS>->set_tls( %OPTS )

Creates a new entry in the datastore.

%OPTS is:

=over

=item C<domain> - The domain whose certificate you’re installing.
(This matches the NAME argument in other calls documented for this module.)

=item C<certificate> - The certificate, either in PEM format or as a
L<Cpanel::SSL::Objects::Certificate> instance.

=item C<key> - The private key, in PEM format.

=item C<cabundle> - The CA bundle, in line-delimited PEM format. Not needed
(in fact, should B<NOT> be given> if the certificate is self-signed or
otherwise doesn’t need an intermediate trust chain.

=back

This will remove any pending unset queue entry for the given C<domain>.

There is a bit of validation here: we verify that the key and signature
are both “strong enough” for the current system. (e.g., no SHA-1 or MD5
signatures, and no 1,024-bit RSA keys) It also verifies that the
certificate has not been revoked.

=cut

sub set_tls {
    my ( $class, %opts ) = @_;
    my ( $domain, $certificate, $key, $cabundle ) = @opts{
        qw(
          domain
          certificate
          key
          cabundle
        )
    };

    my $c_obj = _normalize_certificate_obj($certificate);

    if ( !$c_obj->is_self_signed() ) {
        if ( length $cabundle ) {
            require Cpanel::SSL::Utils;
            $cabundle = Cpanel::SSL::Utils::normalize_cabundle_order($cabundle);
        }

        #NB: We used to fetch a CA bundle here, but we should really have the
        #full CA chain by this point.

        if ( $c_obj->revoked($cabundle) ) {
            die Cpanel::Exception::create( 'InvalidParameter', 'This certificate has been revoked.' );
        }
    }

    $class->_set_tls__no_verify__crt_obj(
        %opts,
        cabundle    => $cabundle,
        certificate => $c_obj,
    );

    return;
}

=head2 I<CLASS>->set_tls__no_verify( %OPTS )

Same as C<set_tls()> except that we don’t verify the non-revocation status.

=cut

sub set_tls__no_verify {
    my ( $class, %opts ) = @_;

    my $c_obj = _normalize_certificate_obj( $opts{'certificate'} );

    return $class->_set_tls__no_verify__crt_obj(
        %opts,
        certificate => $c_obj,
    );
}

#----------------------------------------------------------------------

=head2 $removed_yn = I<CLASS>->unset_tls( NAME )

B<DO NOT USE> unless you absolutely need to delete an entry immediately
and are absolutely sure that no production process will expect the
certificate to be there.

Most of the time you should use C<enqueue_unset_tls()> instead.

Removes an entry immediately. Returns 1 if an entry was removed, and
0 if there was no entry to remove.

=cut

#Returns 1 if removed; 0 if it wasn’t there in the first place.
*unset_tls = *_unset_tls_in_filesystem;

#----------------------------------------------------------------------

#Called from subclass
sub __enqueue_unset_tls_no_task_queue {
    my ( $class, $names_ar ) = @_;

    my $lock;

    local ( $!, $^E, $@ );

    my $did_init;

    my $removed = 0;

    for my $name (@$names_ar) {
        next if !$class->has_tls($name);

        # Only get a lock if we are going to
        # create the pending delete file
        if ( !$lock ) {
            $lock = $class->__get_write_lock();
            next if !$class->has_tls($name);    # check again since we now have a lock
        }

        my $touchfile = $class->_get_pending_delete_path($name);

        if ( sysopen my $wfh, $touchfile, _PENDING_DELETE_PATH_FLAGS() ) {
            $removed++;
        }
        else {
            if ( $! != _EEXIST ) {
                if ( !$did_init && $! == _ENOENT() ) {
                    $class->init();
                    $did_init = 1;
                    redo;
                }
            }

            my $err = Cpanel::Exception::create( 'IO::FileCreateError', [ path => $touchfile, error => $! ] );

            #Bail out if we fail without having made any prior changes.
            die $err if !$removed;

            warn "Failed to create $touchfile after $removed success(es) on other files: $err";
        }
    }

    return $removed;
}

sub _clear_unset_queue_entry {
    my ( $class, $name ) = @_;

    return Cpanel::Autodie::unlink_if_exists( $class->_get_pending_delete_path($name) );
}

#subclass can override, e.g., if it has its own locking mechanism
sub __get_write_lock {
    my ($class) = @_;

    my $path = $class->BASE_PATH() . '/.lock';

    Cpanel::Autodie::open( my $wfh, '>', $path );

    Cpanel::FileUtils::Flock::flock( $wfh, 'EX' );

    return $wfh;
}

sub _unset_tls_in_filesystem {
    my ( $class, $domain ) = @_;

    my $old_path = $class->_get_entry_dir($domain);

    my $rename_to = $class->_get_temp_domain_dir($domain);

    return 0 if !Cpanel::Autodie::rename_if_exists( $old_path, $rename_to );

    local ( $!, $^E );
    for my $fn (qw( combined certificates )) {
        unlink "$rename_to/$fn" or warn "unlink($rename_to/$fn): $!";
    }
    for my $fn (qw( combined.cache certificates.cache )) {
        unlink "$rename_to/$fn" or do {
            warn "unlink($rename_to/$fn): $!" if $! != _ENOENT();
        };
    }

    $class->_clear_unset_queue_entry($domain);

    rmdir $rename_to or warn "rmdir($rename_to): $!";

    return 1;
}

sub _rename_in_filesystem {
    my ( $class, $old, $new ) = @_;

    my $old_path = $class->_get_entry_dir($old);
    my $new_path = $class->_get_entry_dir($new);

    my $lock = $class->__get_write_lock();

    #We do this separately from the rename() because has_tls()
    #factors in a pending deletion. If we only used the filesystem
    #we’d rename things that are pending deletion, which would require
    #a replacement task queue entry, etc.
    return 0 if !$class->has_tls($old);

    my $ret;
    try {
        $ret = Cpanel::Autodie::rename_if_exists( $old_path, $new_path );
    }
    catch {
        local $@ = $_;
        die if !try { $_->isa('Cpanel::Exception::IO::RenameError') };
        die if $_->error_name() ne 'EEXIST' && $_->error_name ne 'ENOTEMPTY';

        # If the new domain already has tls we should not
        # overwrite ite.
        die if $class->has_tls($new);

        #If the failure was because there is already an entry
        #for this $domain, then we want to remove the old one and retry.
        $class->_unset_tls_in_filesystem($new);
        $ret = Cpanel::Autodie::rename( $old_path, $new_path );
    };

    return $ret;
}

sub _get_temp_domain_dir {
    my ( $class, $domain ) = @_;

    require Cpanel::Time::ISO;

    return $class->BASE_PATH() . '/' . join(
        '.',
        q<>,    #so we get “.” as the first character
        substr( $domain, 0, Cpanel::Linux::Constants::NAME_MAX() - 50 ),
        Cpanel::Time::ISO::unix2iso(),
        $$,
        substr( rand, 2 ),
    );
}

#So this can be suppressed.
sub _ensure_certificate_object_matches_entry {
    my ( $class, $crt_obj, $domain ) = @_;

    if ( !grep { Cpanel::WildcardDomain::wildcard_domains_match( $_, $domain ) } @{ $crt_obj->domains() } ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'This certificate does not secure the domain “[_1]”.', [$domain] );
    }

    return;
}

sub _set_tls__no_verify__crt_obj {
    my ( $class, %opts ) = @_;
    my ( $domain, $crt_obj, $key, $cabundle ) = @opts{
        qw(
          domain
          certificate
          key
          cabundle
        )
    };

    $crt_obj->verify_key_is_strong_enough();
    $crt_obj->verify_signature_algorithm_is_strong_enough();

    _ensure_cert_matches_key( $crt_obj, $key );

    if ( $crt_obj->is_self_signed() && length $cabundle ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'This certificate is self-signed, but you submitted a [output,abbr,CA,Certificate Authority] bundle with it.' );
    }

    $class->_ensure_certificate_object_matches_entry( $crt_obj, $domain );

    if ( length $cabundle ) {
        require Cpanel::SSL::Utils;
        $cabundle = Cpanel::SSL::Utils::normalize_cabundle_order($cabundle);
    }
    else {
        $cabundle = q<>;
    }

    my $cert_pem = $crt_obj->text();

    do { s<^\s+><>s; s<\s+$><>s; tr<\n><>s }
      for ( $key, $cert_pem, $cabundle );

    my @pem = ( $key, $cert_pem, $cabundle || () );

    my $final_path = $class->_get_entry_dir($domain);

    my $temp_path = $class->_get_temp_domain_dir($domain);

    try {
        Cpanel::Autodie::mkdir($temp_path);
    }
    catch {

        #If the failure was nonexistence of the BASE_PATH, then
        #run init(), and retry. This will be rare in production but
        #not uncommon in testing.
        local $@ = $_;
        die if !try { $_->isa('Cpanel::Exception::IO::DirectoryCreateError') };
        die if $_->error_name() ne 'ENOENT';

        $class->init();
        Cpanel::Autodie::mkdir($temp_path);
    };

    my @combined_owner_ids = $class->_COMBINED_OWNER_IDS($domain);

    try {
        #Write the combined file--which includes the key.
        Cpanel::Autodie::open( my $cmb_wfh, '>', "$temp_path/combined" );

        if (@combined_owner_ids) {
            Cpanel::Autodie::chown(
                @combined_owner_ids,
                $cmb_wfh,
            );
        }

        Cpanel::Autodie::chmod( 0640, $cmb_wfh );
        Cpanel::Autodie::print( $cmb_wfh, join( "\n", @pem ) );
        Cpanel::Autodie::close($cmb_wfh);

        #Write the certificates. These are public.
        Cpanel::Autodie::open( my $crt_wfh, '>', "$temp_path/certificates" );
        Cpanel::Autodie::print(
            $crt_wfh,
            join( "\n", $cert_pem, $cabundle || () ),
        );
        Cpanel::Autodie::close($crt_wfh);

        my $lock = $class->__get_write_lock();

        # If it already exists replace the files
        # We always do the combined file first
        #
        # There is a race condition where combined and certificates
        # will differ so we always want to replace combined first
        # since that is what apache will use
        my $exists = Cpanel::Autodie::rename_if_exists( "$temp_path/combined" => "$final_path/combined" );
        if ($exists) {
            Cpanel::Autodie::rename( "$temp_path/certificates" => "$final_path/certificates" );
        }
        else {
            Cpanel::Autodie::rename( $temp_path, $final_path );
        }

        my $pending_touchfile = $class->_get_pending_delete_path($domain);

        try {
            Cpanel::Autodie::unlink_if_exists($pending_touchfile);
        }
        catch {
            warn "unlink($pending_touchfile): $!";
        };
    }
    catch { die $_ }
    finally {
        Cpanel::Autodie::unlink_if_exists("$temp_path/combined");
        Cpanel::Autodie::unlink_if_exists("$temp_path/certificates");
        Cpanel::Autodie::rmdir_if_exists($temp_path);
    };

    _build_certificate_cache( $final_path, $crt_obj, $cabundle );

    return 1;
}

sub _ensure_cert_matches_key {
    my ( $c_obj, $k_pem ) = @_;

    require Cpanel::SSL::Utils;
    my ( $ok, $key_hr ) = Cpanel::SSL::Utils::parse_key_text($k_pem);
    die $key_hr if !$ok;

    my $match_yn = $key_hr->{'key_algorithm'} eq $c_obj->key_algorithm();

    if ($match_yn) {
        Cpanel::Crypt::Algorithm::dispatch_from_parse(
            $key_hr,
            rsa => sub {
                $match_yn = $key_hr->{'modulus'} eq $c_obj->modulus();
                $match_yn &&= $key_hr->{'public_exponent'} eq $c_obj->public_exponent();
            },
            ecdsa => sub {
                $match_yn = $key_hr->{'ecdsa_curve_name'} eq $c_obj->ecdsa_curve_name();
                $match_yn &&= $key_hr->{'ecdsa_public'} eq $c_obj->ecdsa_public();
            },
        );
    }

    if ( !$match_yn ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'The given certificate does not match the given key.' );
    }

    return ( $c_obj, $key_hr );
}

my $_cached_mail_gid;
sub _mail_gid { return ( $_cached_mail_gid ||= ( Cpanel::PwCache::getpwnam('mail') )[3] ) }

sub _COMBINED_OWNER_IDS { return ( 0, _mail_gid() ) }

sub _normalize_certificate_obj {
    my ($pem_or_obj) = @_;

    if ( try { $pem_or_obj->isa('Cpanel::SSL::Objects::Certificate') } ) {
        return $pem_or_obj;
    }
    require Cpanel::SSL::Objects::Certificate;
    return Cpanel::SSL::Objects::Certificate->new( cert => $pem_or_obj );
}

sub _build_certificate_cache {
    my ( $final_path, $crt_obj, $cabundle ) = @_;

    # Force building the cache
    require Cpanel::SSL::Objects::Certificate::File;
    bless $crt_obj, 'Cpanel::SSL::Objects::Certificate::File';
    $crt_obj->set_extra_certificates($cabundle);
    Cpanel::SSL::Objects::Certificate::File->write_cache( "$final_path/combined", $crt_obj );
    $crt_obj->set_extra_certificates('');

    # Now link the cache to the certificates without having
    # to write a new a new file or redump the JSON data
    Cpanel::Autodie::unlink_if_exists( "$final_path/certificates" . Cpanel::SSL::Objects::Certificate::File::CACHE_SUFFIX() );
    Cpanel::Autodie::link( "$final_path/combined" . Cpanel::SSL::Objects::Certificate::File::CACHE_SUFFIX(), "$final_path/certificates" . Cpanel::SSL::Objects::Certificate::File::CACHE_SUFFIX() );
    return;
}
1;
