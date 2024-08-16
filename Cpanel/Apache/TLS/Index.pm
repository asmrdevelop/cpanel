package Cpanel::Apache::TLS::Index;

# cpanel - Cpanel/Apache/TLS/Index.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Apache::TLS::Index - index DB for Apache’s SSL/TLS resources

=head1 SYNOPSIS

    $atls_idx = Cpanel::Apache::TLS::Index->new();

    # Queries: --------------------------------------------------

    $one_record_or_undef = $atls_idx->get_for_vhost('some.vhost.tld');

    @records = $atls_idx->get_for_certificate_id( $sslstorage_cert_id);

    @records = $atls_idx->get_for_rsa_modulus( $rsa_modulus_hex );

    @records = $atls_idx->get_for_ecdsa_curve_and_point(
        'prime256v1', $public_hex
    );

    #This returns a reference rather than a list because of the likelihood
    #that it wil return a very long list on servers with AutoSSL enabled.
    $all_records_ar = $atls_idx->get_all_ar();

    # Writes: --------------------------------------------------

    $xaction_obj = $atls_idx->start_transaction();

    $count = $atls_idx->set( $vhost_name, $certificate_pem );

    $count = $atls_idx->unset($vhost_name);

    $count = $atls_idx->rename( $old_vhost_name => $new_vhost_name );

    #^^ Each of the above is assumed to require additional updates that
    #should happen *after* the DB update but *before* the call to release().
    #See below for details.

    $xaction->release();

=head1 DESCRIPTION

This module encapsulates logic to deal with Apache TLS’s database index.
It’s essentially a cache of a certificate parse and validation, indexed to
the virtual host that uses a certificate.

=head1 WRITES

Write methods for this class are meant to occur together with a filesystem
update (cf. L<Cpanel::Apache::TLS::Write>). If the filesystem update fails,
we want the DB update to roll back. Toward that end, each update to the DB
must occur while a transaction object exists.

The normal workflow for this is as shown in the SYNOPSIS:

=over

=item 1) Create the transaction—i.e., store C<start_transaction()>’s
result in a variable.

=item 2) Update the DB.

=item 3) Update the rest of the system. If any of these fails, C<die()>.

=item 4) If all is well, call the transaction object’s C<release()> method.

=back

If the transaction object is DESTROYed without a call to C<release()>,
then the DB changes are rolled back, and a warning is produced. This
ensures that any failure is reported.

=head1 READ METHODS

=cut

use Cpanel::Apache::TLS      ();
use Cpanel::Context          ();
use Cpanel::Crypt::Algorithm ();
use Cpanel::Crypt::Constants ();
use Cpanel::Debug            ();
use Cpanel::SQLite::Compat   ();

our $_WARN_ON_RECREATE = 1;

=head2 $obj = I<CLASS>->new()

Instantiates the class. If the database needs to be recreated,
then it will also rebuild the data. This is what you should
call normally.

=cut

sub new {
    my ($class) = @_;

    local $Cpanel::Apache::TLS::Index::DB::_RECREATED;

    my $self = $class->_new_without_rebuild();

    if ($Cpanel::Apache::TLS::Index::DB::_RECREATED) {
        if ($_WARN_ON_RECREATE) {
            Cpanel::Debug::log_warn("The system has recreated the Apache TLS index database. Rebuilding entries …\n");
        }

        require Cpanel::Apache::TLS::RebuildIndex;
        my $xaction = Cpanel::Apache::TLS::RebuildIndex::rebuild_all($self);
        $xaction->release();

        if ($_WARN_ON_RECREATE) {
            Cpanel::Debug::log_warn("Apache TLS entries rebuilt.\n");
        }
    }

    return $self;
}

=head2 I<CLASS>->new_without_rebuild()

Instantiates the class. If the database needs to be recreated,
then it will only recreate the database and schema; it will NOT rebuild
the data. You should thus probably only call this
if you’re instantiating for the purpose of rebuilding the data.

=cut

sub new_without_rebuild {
    my ($class) = @_;

    local $Cpanel::Apache::TLS::Index::DB::_RECREATED;

    return $class->_new_without_rebuild();
}

=head2 $record_or_undef = I<OBJ>->get_for_vhost( VHOST_NAME )

Returns the record, if any, for the given virtual host in the database.
If there is no record for the given virtual host, undef is returned.

Each record is a hash reference:

=over

=item * C<vhost_name> - The name of the installed virtual host.
(For Apache this is currently identical to the domain name in the C<ServerName>
directive, minus cPanel’s wildcard encoding.) This is the primary key;
no two records will have the same value for this field.

=item * C<subject> - The certificate’s subject DN, expressed as a
newline-joined list of C<$key=$value>. This assumes that each RDN contains
only a single value—which seems to be a safe assumption for X.509
certificates.

=item * C<issuer> - The certificate’s issuer DN, in the same format as
C<subject>.

B<NOTE>: A self-signed certificate will have the same text for C<issuer>
as for C<subject>.

=item * C<not_after> - The certificate’s C<notAfter> time, represented in
ISO 8601 “Zulu” time (cf. L<Cpanel::Time::ISO>).

=item * C<not_before> - The certificate’s C<notBefore> time, also in
ISO 8601 “Zulu” time.

=item * C<encryption_algorithm> - The certificate’s key encryption algorithm,
e.g., C<rsaEncryption>.

=item * C<signature_algorithm> - The certificate’s signature algorithm, e.g.,
C<sha256WithRSAEncryption>.

=item * C<certificate_domains> - The domains that the certificate secures.
This is a combination of the subject’s C<commonName> value (there shouldn’t
be more than one?!?) and the C<subjectAltName> extension’s C<dNSName> values.
They appear in the same order as in the certificate.

=item * C<validation_type> - The validation type as returned from
C<Cpanel::SSL::Utils::parse_certificate_text()>.

=item * C<certificate_id> - The certificate’s SSLStorage ID, as given by
C<Cpanel::SSLStorage::Utils::make_certificate_id()>.

=back

RSA-encrypted certificates (i.e., C<encryption_algorithm> is C<rsaEncryption>)
have the following additional items:

=over

=item * C<public_exponent> - The key’s public exponent, expressed as a
lower-case hexadecimal string. This is usually C<010001> (65,537).

=item * C<modulus_length> - The bit length of the key’s modulus, e.g., 2048.

=item * C<modulus> - The key’s modulus, expressed as a lower-case hexadecimal
string.

=back

=cut

sub get_for_vhost {
    my ( $self, $vhost ) = @_;

    my $all_ar = $self->{'_dbh'}->selectall_arrayref( 'SELECT * FROM vhost_certificates WHERE vhost_name=?', { Slice => {} }, $vhost );

    return @$all_ar ? _xform_read( $all_ar->[0] ) : undef;
}

=head2 $records = I<OBJ>->get_for_vhost( VHOST_NAME1, VHOST_NAME2, ... VHOST_NAME(N) )

For when you need a lot of records.  Automatically chunks your request around SQLite's ? interpolation limit in an IN constrant.
This translates into 1 query per 999 domains.  It would have been preferred we have had a mapping table to username, but here we are.

Converts to a hashref for ease of use:

    {
        'some.host' => {
            ...
        },
        ...
    }

=cut

sub get_for_vhosts {
    my ( $self, @vhosts ) = @_;

    my %all;
    while ( scalar(@vhosts) ) {
        my @vh_slice = splice( @vhosts, 0, 999 );
        my $qs       = join( ',', map { '?' } @vh_slice );
        my $all_ar   = $self->{'_dbh'}->selectall_arrayref( "SELECT * FROM vhost_certificates WHERE vhost_name IN ($qs)", { Slice => {} }, @vh_slice );
        foreach my $entry (@$all_ar) {
            $all{ $entry->{vhost_name} } = _xform_read($entry);
        }
    }

    return \%all;
}

=head2 @records = I<OBJ>->get_for_certificate_id( CERTIFICATE_ID )

Returns records that have the given SSLStorage certificate ID
(cf. C<Cpanel::SSLStorage::Utils::make_certificate_id()>). Note that the same
certificate can be installed onto multiple Apache virtual hosts.

=cut

sub get_for_certificate_id {
    my ( $self, $cert_id ) = @_;

    Cpanel::Context::must_be_list();

    my $all_ar = $self->{'_dbh'}->selectall_arrayref( 'SELECT * FROM vhost_certificates WHERE certificate_id = ?', { Slice => {} }, $cert_id );

    _xform_read($_) for @$all_ar;

    return @$all_ar;
}

=head2 @records = I<OBJ>->get_for_rsa_modulus( LC_HEX_MODULUS )

Returns records that have the given RSA modulus. The given modulus should be
in lower-case hex. Note that the same key can be active on multiple Apache
virtual hosts at the same time—possibly on separate certificates, but more
likely on a single, multiply-installed certificate.

This matching is predicated on the idea that two RSA keys with the same
modulus are actually the same key; however, this isn’t quite true because
two different RSA keys B<can> have the same modulus but different public
exponents. Because the public exponent is likely the same on all
locally-generated keys, though, and modulus collisions should be very
rare besides, in practice it’s “good enough”.

=cut

sub get_for_rsa_modulus {
    my ( $self, $modulus_hex ) = @_;

    if ( $modulus_hex =~ tr<0-9a-f><>c ) {
        die "Invalid modulus: [$modulus_hex]";
    }

    Cpanel::Context::must_be_list();

    my $all_ar = $self->{'_dbh'}->selectall_arrayref( 'SELECT * FROM vhost_certificates WHERE _encryption_id LIKE ? AND encryption_algorithm = ?', { Slice => {} }, "% $modulus_hex", Cpanel::Crypt::Constants::ALGORITHM_RSA );

    _xform_read($_) for @$all_ar;

    return @$all_ar;
}

=head2 @records = I<OBJ>->get_for_ecdsa_curve_and_point( $CURVE_NAME, $POINT_HEX )

Like C<get_for_rsa_modulus()> but for ECDSA keys. Requires two parameters:

=over

=item * the curve name, as given by L<Cpanel::Crypt::ECDSA::Data>’s
C<ACCEPTED_CURVES> constant.

=item * the public point, uncompresed, in lower-case hex

=back

=cut

sub get_for_ecdsa_curve_and_point ( $self, $curve_name, $point_hex ) {
    require Cpanel::Crypt::ECDSA::Validate;

    Cpanel::Crypt::ECDSA::Validate::validate_curve_name_and_point(
        $curve_name, $point_hex,
    );

    Cpanel::Context::must_be_list();

    my $all_ar = $self->{'_dbh'}->selectall_arrayref( 'SELECT * FROM vhost_certificates WHERE encryption_algorithm = ? AND _encryption_id = ? AND _encryption_detail = ?', { Slice => {} }, Cpanel::Crypt::Constants::ALGORITHM_ECDSA, $point_hex, $curve_name );

    _xform_read($_) for @$all_ar;

    return @$all_ar;
}

=head1 $all_records_ar = I<OBJ>->get_all_ar()

Returns an array reference with all records in the database. Note that
this returns an array reference (not a list literal) because of the potential
for very long lists (1,000s of entries) on AutoSSL-enabled systems.

=cut

sub get_all_ar {
    my ($self) = @_;

    my $all_data = $self->{'_dbh'}->selectall_arrayref( 'SELECT * FROM vhost_certificates', { Slice => {} } );

    _xform_read($_) for @$all_data;

    return $all_data;
}

sub _xform_read {
    my ($row) = @_;

    $row->{'certificate_domains'} = [ split m</>, substr( $row->{'certificate_domains'}, 1 ) ];

    my $encryption_id     = delete $row->{'_encryption_id'};
    my $encryption_detail = delete $row->{'_encryption_detail'};

    # For dispatch_from_parse()’s sake …
    local $row->{'key_algorithm'} = $row->{'encryption_algorithm'};

    Cpanel::Crypt::Algorithm::dispatch_from_parse(
        $row,
        rsa => sub {
            @{$row}{ 'public_exponent', 'modulus' } = split m< >, $encryption_id;
            $row->{'modulus_length'} = $encryption_detail;
        },
        ecdsa => sub {
            @{$row}{ 'ecdsa_curve_name', 'ecdsa_public' } = (
                $encryption_detail,
                $encryption_id,
            );
        },
    );

    return $row;
}

#----------------------------------------------------------------------

=head1 WRITE METHODS

=head2 $xaction = I<OBJ>->start_transaction( NAME )

NAME is an arbitrary name that will make the warning on failure more
meaningful.

Returns a transaction object. This needs to happen before you can make
changes to the database. If the transaction object is DESTROYed without
a call to its C<release()> method, any changes to the database are rolled
back, and a warning is thrown.

B<NOTE:> B<Always> call C<release()> when you’re done and there’s
no error, even if you didn’t actually do anything to update the DB.

For the time being there is no way to rollback without the warning;
it’s forseeable that we may need a dedicated C<rollback()> method, but
for now it’s not needed.

=cut

sub start_transaction {
    my ( $self, $name ) = @_;

    return Cpanel::Apache::TLS::Index::Transaction->new(
        $self->{'_dbh'},
        $name,
    );
}

#----------------------------------------------------------------------

=head2 $count = I<OBJ>->set( VHOST_NAME, CERTIFICATE_OBJECT )

VHOST_NAME is the virtual host name, and CERTIFICATE_OBJECT is an instance
of L<Cpanel::SSL::Objects::Certificate>.

This will update any existing record for the given VHOST_NAME. This returns
the number of entries created/updated, which is probably 1.

=cut

my @_key_order = (
    'vhost_name',
    'signature_algorithm',
    'validation_type',
    'certificate_domains',
    'certificate_id',
    'not_after',
    'not_before',
    'subject',
    'issuer',
    'encryption_algorithm',
    '_encryption_detail',
    '_encryption_id',
);

sub set {
    my ( $self, $vhost_name, $cert_obj ) = @_;

    $self->_verify_transaction();

    require Cpanel::SSLStorage::Utils;
    require Cpanel::Time::ISO;

    my ( $c_ok, $cert_id ) = Cpanel::SSLStorage::Utils::make_certificate_id($cert_obj);
    die "make cert ID: $cert_id" if !$c_ok;

    my ( $enc_detail, $enc_id );

    Cpanel::Crypt::Algorithm::dispatch_from_object(
        $cert_obj,
        rsa => sub {
            ( $enc_detail, $enc_id ) = (
                $cert_obj->modulus_length(),
                join(
                    q< >,
                    $cert_obj->public_exponent(),
                    $cert_obj->modulus(),
                ),
            );
        },
        ecdsa => sub {
            ( $enc_detail, $enc_id ) = (
                $cert_obj->ecdsa_curve_name(),
                $cert_obj->ecdsa_public(),
            );
        },
    );

    my %data = (
        vhost_name          => $vhost_name,
        signature_algorithm => $cert_obj->signature_algorithm(),
        validation_type     => $cert_obj->validation_type(),
        certificate_domains => join( '/', q<>, @{ $cert_obj->domains() }, q<> ),
        certificate_id      => $cert_id,

        not_after  => Cpanel::Time::ISO::unix2iso( $cert_obj->not_after() ),
        not_before => Cpanel::Time::ISO::unix2iso( $cert_obj->not_before() ),

        subject => _encode_dn_ar( $cert_obj->subject_list() ),
        issuer  => _encode_dn_ar( $cert_obj->issuer_list() ),

        #NB: these will be updated for ECC once we support it
        encryption_algorithm => $cert_obj->key_algorithm(),
        _encryption_detail   => $enc_detail,
        _encryption_id       => $enc_id,
    );

    return $self->_set_vhost_certificate( \%data );
}

sub _set_vhost_certificate {
    my ( $self, $data_hr ) = @_;

    if ( !$self->{'_set_vhost_certificate_query'} ) {
        my $keys_str   = join( ',', @_key_order );
        my $values_str = join( ',', ( ('?') x @_key_order ) );
        $self->{'_set_vhost_certificate_query'} = $self->{'_dbh'}->prepare("INSERT OR REPLACE INTO vhost_certificates ($keys_str) VALUES ($values_str)");
    }

    my @values = map { $data_hr->{$_} } @_key_order;

    return 0 + $self->{'_set_vhost_certificate_query'}->execute(@values);

}

#----------------------------------------------------------------------

=head2 $count = I<OBJ>->unset( VHOST_NAME )

Remove the entry, if any, for the given vhost name. Returns 1 if a record
was removed or 0 if not.

=cut

sub unset {
    my ( $self, $vhost_name ) = @_;

    $self->_verify_transaction();

    return 0 + $self->{'_dbh'}->do( 'DELETE FROM vhost_certificates WHERE vhost_name=?', undef, $vhost_name );
}

#----------------------------------------------------------------------

=head2 $count = I<OBJ>->purge_all()

Remove every entry from the table.

=cut

sub purge_all {
    my ($self) = @_;

    $self->_verify_transaction();

    return 0 + $self->{'_dbh'}->do('DELETE FROM vhost_certificates');
}

#----------------------------------------------------------------------

=head2 $count = I<OBJ>->rename( OLD_VHOST_NAME => NEW_VHOST_NAME )

Rename the entry, if any, for the given vhost name. Returns 1 if a record
was renamed or 0 if not.

=cut

sub rename {
    my ( $self, $old, $new ) = @_;

    $self->_verify_transaction();

    return 0 + $self->{'_dbh'}->do( 'UPDATE vhost_certificates SET vhost_name=? WHERE vhost_name=?', undef, $new, $old );
}

#----------------------------------------------------------------------

sub _encode_dn_ar {
    my ($dn_ar) = @_;

    # RFC 2253 describes the standard format for notating fields like this;
    # however, it’s much simpler just to use newline-delimited lists
    # of type/value pairs. This assumes that the field (as represented
    # in ASN.1) doesn’t contain any multi-value RDNs--which seems a safe
    # assumption for X.509 certificates.
    return join( "\n", map { "$_->[0]=$_->[1]" } @$dn_ar );
}

#Any write changes need to happen to the filesystem as well as to the DB;
#thus, let’s ensure that the calling logic appears correct.
sub _verify_transaction {
    my ($self) = @_;

    if ( !$Cpanel::Apache::TLS::Index::Transaction::_CURRENT_TRANSACTION_NAME ) {
        die "must be in a transaction!";
    }

    return;
}

sub _new_without_rebuild {
    my ($class) = @_;

    my $dbh = Cpanel::Apache::TLS::Index::DB->dbconnect();
    if ( !$dbh ) {

        #We don’t know why the failure happened, but maybe it was
        #because the filesystem structure isn’t in place?
        require Cpanel::Apache::TLS::Write;
        Cpanel::Apache::TLS::Write->init();

        $dbh = Cpanel::Apache::TLS::Index::DB->dbconnect() || die "Apache TLS connect error - check log";
    }

    #This DB was errantly created non-WAL for a while;
    #this ensures that that’s fixed.
    Cpanel::SQLite::Compat::upgrade_to_wal_journal_mode_if_needed($dbh);

    my $self = {
        _xaction => undef,
        _dbh     => $dbh,
    };

    return bless $self, $class;
}

#----------------------------------------------------------------------

package Cpanel::Apache::TLS::Index::Transaction;

our $_CURRENT_TRANSACTION_NAME;

sub new {
    my ( $class, $dbh, $name ) = @_;

    if ($_CURRENT_TRANSACTION_NAME) {
        die "Already in a transaction ($_CURRENT_TRANSACTION_NAME); can’t create new transaction “$name”!";
    }

    $_CURRENT_TRANSACTION_NAME = $name;

    #“IMMEDIATE” creates an SQLite “RESERVED” lock, which allows other
    #processes to read but forbids any writes or other RESERVEDs.
    #
    #We use this rather than the default DEFERRED transaction because of
    #cases like rebuilding the DB, where we want to ensure right away that
    #nothing else will write to the DB.
    $dbh->do('BEGIN IMMEDIATE TRANSACTION');

    return bless {
        name => $name,
        dbh  => $dbh,
    }, $class;
}

sub release {
    my ($self) = @_;

    $self->{'dbh'}->commit();

    #Our work is done here.
    $self->_clear();

    return;
}

sub DESTROY {
    my ($self) = @_;

    if ( $self->{'dbh'} ) {
        warn "Rolling back unreleased transaction “$self->{'name'}”!";

        $self->{'dbh'}->rollback();
        $self->_clear();
    }

    return;
}

sub _clear {
    my ($self) = @_;

    delete $self->{'dbh'} or warn 'Already cleared!';
    undef $_CURRENT_TRANSACTION_NAME;

    return;
}

#----------------------------------------------------------------------

package Cpanel::Apache::TLS::Index::DB;

use parent qw( Cpanel::SQLite::AutoRebuildSchemaBase );

use Cpanel::Apache::TLS ();

use constant {
    _SCHEMA_NAME    => 'apache_tls_index',
    _SCHEMA_VERSION => 1,
};

our $_RECREATED;

sub _PATH {
    my $base = Cpanel::Apache::TLS->BASE_PATH();

    #The dot-prefixed name will avoid being picked up by the
    #directory-listing logic in get_tls_vhosts().
    return "$base/.index.sqlite";
}

sub _create_db_post {
    $_RECREATED = 1;
    return;
}

1;
