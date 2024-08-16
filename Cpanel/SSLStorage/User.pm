package Cpanel::SSLStorage::User;

# cpanel - Cpanel/SSLStorage/User.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::Crypt::Algorithm             ();
use Cpanel::Quota::Temp                  ();
use Cpanel::SSLStorage::Utils            ();
use Cpanel::SSLStorage                   ();
use Cpanel::AccessIds::ReducedPrivileges ();
use Cpanel::Locale                       ();
use Cpanel::PwCache                      ();
use Cpanel::SSL::Utils                   ();

use parent qw( Cpanel::SSLStorage );

our $SYSTEM_SSL = __PACKAGE__->_BASE_DIRECTORY() . '/system';

my %uniques;

BEGIN {
    %uniques = (
        __PACKAGE__->SUPER::_UNIQUES(),
        csr => ['friendly_name'],
    );

    push @{ $uniques{'key'} },         'friendly_name';
    push @{ $uniques{'certificate'} }, 'friendly_name';
}
use constant _UNIQUES => %uniques;

use constant _INDEXES => (
    __PACKAGE__->SUPER::_INDEXES(),
    csr => [
        'modulus',
        'ecdsa_curve_name',
        'ecdsa_public',
        'commonName',
    ],
);

use constant _EXTENSION => (
    __PACKAGE__->SUPER::_EXTENSION(),
    csr => 'csr',
);

use constant _DIRECTORY => (
    __PACKAGE__->SUPER::_DIRECTORY(),
    csr => 'csrs',
);

use constant _MODE => (
    __PACKAGE__->SUPER::_MODE(),
    csr => 0644,
);

sub _FINDER {
    return (
        __PACKAGE__->SUPER::_FINDER(),
        csr => 'find_csrs',
    );
}

sub _ADD {
    return (
        __PACKAGE__->SUPER::_ADD(),
        csr => 'add_csr',
    );
}

sub _MAKE_ID {
    return (
        __PACKAGE__->SUPER::_MAKE_ID(),
        'csr' => \&Cpanel::SSLStorage::Utils::make_csr_id,
    );
}

sub _TEXT {
    return (
        __PACKAGE__->SUPER::_TEXT(),
        csr => 'get_csr_text',
    );
}

my $locale;

#Accepts a literal hash of the following parameters:
#   user (defaults to $>):
#       The user whose datastore to use, if not "installed".
#   rename_old_friendly_name (boolean)
#       When adding new items, if there is a friendly_name conflict,
#       this flag will tell the object to alter the existing object's
#       friendly_name rather than the new one's. This is undesirable
#       behavior and only exists for legacy implementations (e.g., API2).
#
#
sub new {
    my ( $class, %opts ) = @_;

    my $user = $opts{'user'} ||= Cpanel::PwCache::getusername();

    #Only set "_path" for testing.
    if ( !$opts{'_path'} ) {
        my $path;

        if ( $user eq 'root' ) {
            $path = $SYSTEM_SSL;
        }
        else {
            my $homedir = Cpanel::PwCache::gethomedir($user);

            if ( !$homedir ) {
                return undef if !wantarray;

                _get_locale();
                return ( 0, $locale->maketext( 'The user “[_1]” does not exist.', $user ) );
            }

            $path = "$homedir/ssl";
        }

        $opts{'_path'} = $path;
    }

    $opts{'_rename_old_friendly_name'} = delete $opts{'rename_old_friendly_name'};

    $opts{'_pid'} = $$;

    my $self = \%opts;
    bless $self, $class;

    return $self->_init(%opts);
}

#Accepts a hash of options:
#   text: The text of the key file. (required)
#   friendly_name: An arbitrary description string.
sub add_key {
    my ( $self, %opts ) = @_;

    my ( $ok, $key );
    ( $ok, $key ) = Cpanel::SSL::Utils::get_key_from_text( $opts{'text'} );
    return ( 0, $key ) if !$ok;

    my $new_record;
    ( $ok, $new_record ) = $self->_build_key_record(%opts);
    return ( 0, $new_record ) if !$ok;

    my $msg;
    ( $ok, $msg ) = $self->_add_key_record( $new_record, $key );

    return ( 1, $msg ) if $ok;

    if ( ref $msg && $$msg =~ m/^already_used\s+(\S+)\s+(\S+)$/ ) {
        my ( $param, $id ) = ( $1, $2 );

        #Assume this is ok and that $dupes_ar has one member.
        my ( $ok, $dupes_ar ) = $self->find_keys( id => $id );

        #If the key is already added, then $param will always be "id",
        #even if the friendly_name also matches.
        if ( $param eq 'id' ) {
            if ( $new_record->{'friendly_name'} eq $dupes_ar->[0]{'friendly_name'} ) {
                return ( 1, $new_record );    #Same key, same friendly_name, so return success.
            }

            _get_locale();
            return ( 0, $locale->maketext( 'That key is already installed as “[_1]”.', $dupes_ar->[0]{'friendly_name'} ) );
        }

        _get_locale();

        return ( 0, $locale->maketext( 'Your key “[_1]” already has the same “[_2]” ([_3]) as the new key. Each key’s “[_2]” must be unique.', $id, $param, $new_record->{$param} ) );
    }

    return ( 0, $msg );
}

#Accepts a hash of options:
#   text: The text of the certificate file. (required)
#   friendly_name: An arbitrary description string.
sub add_certificate {
    my ( $self, %opts ) = @_;

    my ( $ok, $cert );
    ( $ok, $cert ) = Cpanel::SSL::Utils::get_certificate_from_text( $opts{'text'} );
    return ( 0, $cert ) if !$ok;

    my $new_record;
    ( $ok, $new_record ) = $self->_build_certificate_record(%opts);
    return ( 0, $new_record ) if !$ok;

    my $msg;
    ( $ok, $msg ) = $self->_add_certificate_record( $new_record, $cert );

    return ( 1, $msg ) if $ok;

    if ( ref $msg && $$msg =~ m/^already_used\s+(\S+)\s+(\S+)$/ ) {
        my ( $param, $id ) = ( $1, $2 );

        #Assume this is ok and that $dupes_ar has one member.
        my ( $ok, $dupes_ar ) = $self->find_certificates( id => $id );

        #If the cert is already added, then $param will always be "id",
        #even if the friendly_name also matches.
        if ( $param eq 'id' ) {
            if ( $new_record->{'friendly_name'} eq $dupes_ar->[0]{'friendly_name'} ) {
                return ( 1, $new_record );
            }

            _get_locale();
            return ( 0, $locale->maketext( 'That certificate is already installed as “[_1]”.', $dupes_ar->[0]{'friendly_name'} ) );
        }

        _get_locale();

        return ( 0, $locale->maketext( 'Your certificate for “[_1]” (ID: [_2]) already has the same “[_3]” ([_4]) as the new certificate. Each certificate’s “[_3]” must be unique.', $dupes_ar->[0]{'subject.commonName'}, $id, $param, $new_record->{$param} ) );
    }

    return ( 0, $msg );
}

#Accepts a hash of options:
#   text: The text of the CSR file. (required)
#   friendly_name: An arbitrary description string.
#   created: A timestamp (optional)
sub add_csr {
    my ( $self, %OPTS ) = @_;

    my ( $ok, $csr ) = Cpanel::SSL::Utils::get_csr_from_text( $OPTS{'text'} );
    return ( 0, $csr ) if !$ok;

    ( $ok, my $id ) = Cpanel::SSLStorage::Utils::make_csr_id($csr);
    return ( 0, $id ) if !$ok;

    my $parse;
    ( $ok, $parse ) = Cpanel::SSL::Utils::parse_csr_text($csr);
    return ( 0, $parse ) if !$ok;

    my %key_parts;

    Cpanel::Crypt::Algorithm::dispatch_from_parse(
        $parse,
        rsa => sub {
            $key_parts{'modulus'} = $parse->{'modulus'};
        },
        ecdsa => sub {
            my @names = ( 'ecdsa_curve_name', 'ecdsa_public' );
            @key_parts{@names} = @{$parse}{@names};
        },
    );

    my $new_record = {
        'commonName' => $parse->{'commonName'},
        'domains'    => $parse->{'domains'},
        'id'         => $id,
        'created'    => $OPTS{'created'},

        'key_algorithm' => $parse->{'key_algorithm'},
        %key_parts{ 'modulus', 'ecdsa_curve_name', 'ecdsa_public' },
    };

    ( $ok, $new_record ) = $self->_initialize_new_record( 'csr', $new_record, \%OPTS );
    return ( 0, $new_record ) if !$ok;

    my $msg;
    ( $ok, $msg ) = $self->_save_new(
        'record' => $new_record,
        'type'   => 'csr',
        'text'   => $csr,
    );

    return ( 1, $msg ) if $ok;

    if ( ref $msg && $$msg =~ m/^already_used\s+(\S+)\s+(\S+)$/ ) {
        my ( $param, $id ) = ( $1, $2 );

        #Assume this is ok and that $dupes_ar has one member.
        my ( $ok, $dupes_ar ) = $self->find_csrs( id => $id );

        #If the csr is already added, then $param will always be "id",
        #even if the friendly_name also matches.
        if ( $param eq 'id' ) {
            if ( $new_record->{'friendly_name'} eq $dupes_ar->[0]{'friendly_name'} ) {
                return ( 1, $new_record );
            }

            _get_locale();
            return ( 0, $locale->maketext( 'That CSR is already installed as “[_1]”.', $dupes_ar->[0]{'friendly_name'} ) );
        }

        _get_locale();

        return ( 0, $locale->maketext( 'Your CSR “[_1]” already has the same “[_2]” ([_3]) as the new CSR. Each CSR’s “[_2]” must be unique.', $dupes_ar->[0]{'friendly_name'}, $param, $new_record->{$param} ) );
    }

    return ( 0, $msg );
}

sub find_csrs {
    my ( $self, %query ) = @_;

    my ( $ok, $recs_ar ) = $self->_find( %query, type => 'csr' );

    if ($ok) {
        for my $rec_hr (@$recs_ar) {
            $rec_hr->{$_} //= undef for qw( ecdsa_curve_name  ecdsa_public );
        }
    }

    return ( $ok, $recs_ar );
}

sub get_csr_path {
    my ( $self, $id ) = @_;
    return $self->_get_path( 'csr', $id );
}

sub get_csr_text {
    my ( $self, $id_or_hr ) = @_;
    my ( $ok,   $text )     = $self->_get_text( 'csr', $id_or_hr );

    if ( !$ok && !$text ) {
        my $id = ref($id_or_hr) ? $id_or_hr->{'id'} : $id_or_hr;

        _get_locale();
        $text = $locale->maketext( 'No CSR with the ID “[_1]” exists.', $id );
    }

    return ( $ok, $text );
}

sub remove_csr {
    my ( $self, %opts ) = @_;
    my $id = $opts{'id'};

    return $self->_remove_item(
        'id'   => $id,
        'type' => 'csr',
    );
}

sub set_key_friendly_name {
    my ( $self, $id, $new_val ) = @_;
    my ( $ok, $msg ) = $self->_update_item( 'key', $id, 'friendly_name' => $new_val );

    if ($ok) {
        return ( $ok, $msg );
    }
    else {
        if ( ref $msg ) {
            if ( $$msg =~ m/^already_used\s+(\S+)\s+(\S+)$/ ) {
                my ( $param, $id ) = ( $1, $2 );
                _get_locale();
                return ( 0, $locale->maketext( 'Your key “[_1]” already has that “[_2]”. Each key’s “[_2]” must be unique.', $id, $param ) );
            }
            elsif ( $$msg eq 'id_not_found' ) {
                _get_locale();
                return ( 0, $locale->maketext( 'No key with the ID “[_1]” exists.', $id ) );
            }
        }
        return ( 0, $msg );
    }
}

sub set_certificate_friendly_name {
    my ( $self, $id, $new_val ) = @_;
    my ( $ok, $msg ) = $self->_update_item( 'certificate', $id, 'friendly_name' => $new_val );

    if ($ok) {
        return ( $ok, $msg );
    }
    else {
        if ( ref $msg ) {
            if ( $$msg =~ m/^already_used\s+(\S+)\s+(\S+)$/ ) {
                my ( $param, $id ) = ( $1, $2 );
                _get_locale();
                return ( 0, $locale->maketext( 'Your certificate “[_1]” already has that “[_2]”. Each certificate’s “[_2]” must be unique.', $id, $param ) );
            }
            elsif ( $$msg eq 'id_not_found' ) {
                _get_locale();
                return ( 0, $locale->maketext( 'No certificate with the ID “[_1]” exists.', $id ) );
            }
        }
        return ( 0, $msg );
    }
}

sub set_csr_friendly_name {
    my ( $self, $id, $new_val ) = @_;
    my ( $ok, $msg ) = $self->_update_item( 'csr', $id, 'friendly_name' => $new_val );

    if ($ok) {
        return ( $ok, $msg );
    }
    else {
        if ( ref $msg ) {
            if ( $$msg =~ m/^already_used\s+(\S+)\s+(\S+)$/ ) {
                my ( $param, $id ) = ( $1, $2 );
                _get_locale();
                return ( 0, $locale->maketext( 'Your CSR “[_1]” already has that “[_2]”. Each CSR’s “[_2]” must be unique.', $id, $param ) );
            }
            elsif ( $$msg eq 'id_not_found' ) {
                _get_locale();
                return ( 0, $locale->maketext( 'No CSR with the ID “[_1]” exists.', $id ) );
            }
        }
        return ( 0, $msg );
    }
}

sub expunge_expired_certificates {
    my ($self) = @_;

    return $self->_execute_coderef(
        sub {
            return $self->_expunge_expired_certificates();
        }
    );
}

sub _get_expired_certificates {
    my ($self) = @_;

    my ( $ok, $certs_ar ) = $self->find_certificates();
    if ( !$ok ) {
        $self->_unlock_datastore();
        return ( 0, $certs_ar );
    }

    my $cut_off_time = time() - $Cpanel::SSLStorage::EXPUNGE_CERTIFICATES_AFTER_SECONDS;

    return ( 1, [ grep { $_->{not_after} <= $cut_off_time } @$certs_ar ] );
}

sub _expunge_expired_certificates {
    my ($self) = @_;

    # Try first unlocked
    my ( $ok, $expired_certs ) = $self->_get_expired_certificates();
    if ( !$ok ) {
        return ( 0, $expired_certs );
    }

    if ( !@$expired_certs ) {
        return ( 1, $expired_certs );
    }

    # ok we have some so lets do the removal under the lock
    ( $ok, my $message ) = $self->_load_datastore_rw();
    if ( !$ok ) {
        return ( 0, $message );
    }

    ( $ok, $expired_certs ) = $self->_get_expired_certificates();
    if ( !$ok ) {
        return ( 0, $expired_certs );
    }

    if ($expired_certs) {
        for my $cert (@$expired_certs) {
            ( $ok, $message ) = $self->remove_certificate_and_key( id => $cert->{id} );
            if ( !$ok ) {
                $self->_unlock_datastore();
                return ( 0, $message );
            }
        }

        ( $ok, $message ) = $self->_save_datastore();
        if ( !$ok ) {
            $self->_unlock_datastore();
            return ( 0, $message );
        }
    }
    else {
        $self->_unlock_datastore();
    }

    return ( 1, $expired_certs );
}

#----------------------------------------------------------------------
# Convenience

#TODO: Remove this method and alter everything that calls it. It's
#not multi-domain-savvy.
sub find_key_for_domain {
    my ( $self, $domain ) = @_;

    my ( $ok, $key_record ) = $self->SUPER::find_key_for_domain($domain);
    return ( 0, $key_record ) if !$ok;

    if ( !$key_record ) {
        ( $ok, my $csrs ) = $self->find_csrs( 'commonName' => $domain );
        return ( 0, $csrs ) if !$ok;

        if ( $csrs && @$csrs ) {
            for my $c ( sort { $b->{'not_after'} <=> $a->{'not_after'} } @$csrs ) {
                my ( $ok, $keys ) = $self->find_keys(
                    $self->_get_key_match_params($c),
                );

                if ( $ok && $keys && @$keys ) {
                    $key_record = $keys->[0];
                    last;
                }
            }
        }
    }

    return ( 1, $key_record || undef );
}

#----------------------------------------------------------------------
# Private

sub _build_import_options {
    my ( $self, $record ) = @_;

    return (
        $self->SUPER::_build_import_options($record),
        'friendly_name' => $record->{'data'}{'friendly_name'},
    );
}

#These three functions are for testing:
sub _generate_key_friendly_name {
    my ( $self, $new_record ) = @_;

    my $key_alg = $new_record->{'key_algorithm'} or die 'No key algorithm?';

    _get_locale();

    return Cpanel::Crypt::Algorithm::dispatch_from_parse(
        $new_record,
        rsa => sub {
            my $bits = Cpanel::SSL::Utils::hex_modulus_length( $new_record->{'modulus'} );
            return $locale->maketext( '[numf,_1]-bit [asis,RSA], created [datetime,_2,datetime_format_short] UTC', $bits, time );
        },
        ecdsa => sub {
            return $locale->maketext( '[asis,ECDSA] “[_1]”, created [datetime,_2,datetime_format_short] UTC', $new_record->{'ecdsa_curve_name'}, time );
        },
    );
}

sub _generate_certificate_or_csr_friendly_name {
    my ( $self, $new_record ) = @_;

    _get_locale();
    if ( $self->can('find_keys') ) {
        my %search = $self->_get_key_match_params($new_record);

        my ( $ok, $ret ) = $self->find_keys(%search);

        if ( $ok && ref $ret eq 'ARRAY' ) {
            if ( @{$ret} and ref( $ret->[0] ) eq 'HASH' ) {
                $self->set_key_friendly_name( $ret->[0]->{id}, $locale->list_and( $new_record->{'domains'} ) );
            }
        }
    }

    return $locale->list_and( $new_record->{'domains'} );
}

#This is a hook for subclasses to customize the "add_(key|certificate_csr)"
#parameters when doing a repair().
sub _repair_extra_add_parameters {
    my ( $self, %opts ) = @_;

    my ( $friendly_name, $created );
    if ( $opts{'existing'} ) {
        $friendly_name = $opts{'existing'}{'friendly_name'};
    }

    #In case the ID naming scheme is updated, we want to check if any
    #legacy key entries match (modulus/point); if they do, then use that
    #friendly_name rather than this one.
    #
    #The die() below should never happen except for implementor error
    #because, by getting here, we've already made an ID for this resource
    #and, therefore, parsed it successfully.
    if ( !length $friendly_name && $opts{'type'} eq 'key' ) {
        my ( $ok, $parse ) = Cpanel::SSL::Utils::parse_key_text( ${ $opts{'text'} } );
        die $parse if !$ok;    #See above.

        my %search      = $self->_get_key_match_params($parse);
        my @search_keys = keys %search;

        my @keys = grep {
            my $old = $_;

            !grep { ( $old->{$_} // q<> ) ne ( $parse->{$_} // q<> ) } @search_keys
        } @{ $opts{'old_records'}{'key'} };
        if (@keys) {
            $friendly_name = $keys[0]{'friendly_name'};
            $created       = $keys[0]{'created'};
        }
        else {
            $opts{'path'} =~ m{([^/]+)\z};
            $friendly_name = $1;

            my $extension = $self->_get_extension( $opts{'type'} );
            $friendly_name =~ s{\.\Q$extension\E\z}{};
        }
    }

    #For certs and CSRs, if the file contents' modulus matches only 1 entry
    #from the old ssl.db, then we make a slightly-unsafe assumption that this
    #file matches the old record, and take the friendly_name and created time.
    elsif ( !length $friendly_name && $opts{'type'} eq 'certificate' ) {
        my ( $ok, $parse ) = Cpanel::SSL::Utils::parse_certificate_text( ${ $opts{'text'} } );
        die $parse if !$ok;    #See above.

        my %search      = $self->_get_key_match_params($parse);
        my @search_keys = keys %search;

        my @certificates = grep {
            my $old = $_;

            !grep { ( $old->{$_} // q<> ) ne ( $parse->{$_} // q<> ) } @search_keys
        } @{ $opts{'old_records'}{'certificate'} };

        if ( @certificates == 1 ) {
            $friendly_name = $certificates[0]{'friendly_name'};
            $created       = $certificates[0]{'created'};
        }
    }
    elsif ( !length $friendly_name && $opts{'type'} eq 'csr' ) {
        my ( $ok, $parse ) = Cpanel::SSL::Utils::parse_csr_text( ${ $opts{'text'} } );
        die $parse if !$ok;    #See above.

        my %search      = $self->_get_key_match_params($parse);
        my @search_keys = keys %search;

        my @csrs = grep {
            my $old = $_;

            !grep { ( $old->{$_} // q<> ) ne ( $parse->{$_} // q<> ) } @search_keys
        } @{ $opts{'old_records'}{'csr'} };

        if ( @csrs == 1 ) {
            $friendly_name = $csrs[0]{'friendly_name'};
            $created       = $csrs[0]{'created'};
        }
    }

    return (
        friendly_name => $friendly_name,
        ( $created ? ( created => $created ) : () ),
    );
}

sub _initialize_new_record {
    my ( $self, $type, $new_record, $opts_hr ) = @_;

    my $friendly_name = $opts_hr->{'friendly_name'};
    if ($friendly_name) {
        $friendly_name =~ s{\A\s+|\s+\z}{}g;
    }

    #First check if we're adding a record that already exists.
    my ( $ok, $dupes_ar ) = $self->_find( type => $type, id => $new_record->{'id'} );
    return ( 0, $dupes_ar ) if !$ok;

    if (@$dupes_ar) {

        #If we didn't give a friendly_name, or the one we gave matches the dupe,
        #then just use the dupe's friendly_name.
        if ( !length $friendly_name || $friendly_name eq $dupes_ar->[0]{'friendly_name'} ) {
            $new_record->{'friendly_name'} = $dupes_ar->[0]{'friendly_name'};
        }

        #This will eventually trip an error in base _save_new().
        else {
            $new_record->{'friendly_name'} = $friendly_name;
        }

        return ( 1, $new_record );
    }

    #No friendly_name was given, so we auto-assign.
    if ( !length $friendly_name ) {
        if ( $type eq 'key' ) {
            $friendly_name = $self->_generate_key_friendly_name($new_record);
        }
        elsif ( $type eq 'certificate' || $type eq 'csr' ) {
            $friendly_name = $self->_generate_certificate_or_csr_friendly_name($new_record);
        }
        else {
            die "Invalid type: $type\n";    #Implementor error
        }

        #We only get here if a cert or CSR has no (subject) commonName, which
        #would be pretty useless. But, just in case.
        $friendly_name ||= $locale->maketext( 'Created [datetime,_1,datetime_format_short]', time );
    }

    #A friendly_name must be unique within the datastore;
    #by default, enforce this by assigning a unique friendly_name to new items.
    #Legacy behavior, though, is to rename old items, which happens later on.
    if ( !$self->{'_rename_old_friendly_name'} ) {

        # Try a simple small find first to look for
        # an exact match so we can avoid looking
        # at all the names in the datastore
        my ( $ok, $existing_exact_match_friendly_name ) = $self->_find( type => $type, friendly_name => $friendly_name );
        return ( 0, $existing_exact_match_friendly_name ) if !$ok;

        # If it already exists, lets just try adding the time.loop
        if (@$existing_exact_match_friendly_name) {
            my $original_fn = $friendly_name;
            my $loop_count  = 0;
            while (@$existing_exact_match_friendly_name) {
                my $time_key = _time() . '.' . $loop_count++;
                $friendly_name = "$original_fn $time_key";
                ( $ok, $existing_exact_match_friendly_name ) = $self->_find( type => $type, friendly_name => $friendly_name );
                return ( 0, $existing_exact_match_friendly_name ) if !$ok;
            }
        }
    }

    $new_record->{'friendly_name'} = $friendly_name;

    return ( 1, $new_record );
}

sub _save_new {
    my ( $self, %OPTS ) = @_;

    #Ech. This is nasty, but necessary for backward compatibility.
    if ( $self->{'_rename_old_friendly_name'} ) {
        my $type          = $OPTS{'type'};
        my $friendly_name = $OPTS{'record'}{'friendly_name'};

        my ( $ok, $existing ) = $self->_find( 'type' => $type, 'friendly_name' => $friendly_name );
        return ( 0, $existing ) if !$ok;

        if (@$existing) {
            my $existing_record = $existing->[0];

            #Same friendly_name + same ID == the same entry, so return it.
            if ( $existing_record->{'id'} eq $OPTS{'record'}{'id'} ) {
                return ( 1, $existing_record );
            }

            _get_locale();
            my $alt_friendly_name = $locale->maketext( '[_1], created [datetime,_2,datetime_format_short] UTC', $friendly_name, $existing_record->{'created'} );

            #Just in case there is another item of this type whose friendly_name
            #matches the $alt_friendly_name, increment a number index.
            my $new_friendly_name = $alt_friendly_name;
            ( $ok, $existing ) = $self->_find( 'type' => $type );
            return ( 0, $existing ) if !$ok;    #paranoid

            my %all_items = map { $_->{'friendly_name'} => $_ } @{$existing};
            my $index     = 1;
            while ( $all_items{$new_friendly_name} ) {
                $new_friendly_name = "$alt_friendly_name $index";
                $index++;
            }

            my $err;
            ( $ok, $err ) = $self->_update_item( $type, $existing_record->{'id'}, 'friendly_name' => $new_friendly_name );
            return ( 0, $err ) if !$ok;
        }
    }

    return $self->SUPER::_save_new(%OPTS);
}

sub _init_fs {
    my ($self) = @_;

    $self->_execute_coderef(
        sub {

            my $path = $self->{'_path'};

            #$path should be a directory; if it's not:
            #   as root: fail
            #   as user: attempt to rename the existing filesystem node
            if ( -e $path && !-d _ ) {
                if ( $self->{'user'} eq 'root' ) {
                    _get_locale();
                    return ( 0, $locale->maketext( '“[_1]” is a file, but it should be a directory.', $path ) );
                }
                else {
                    my $moved = "$path.moved_away." . time();
                    if ( !rename( $path, $moved ) ) {
                        _get_locale();
                        return ( 0, $locale->maketext( 'The system could not rename “[_1]” to “[_2]” because of an error: [_3]', $path, $moved, $! ) );
                    }
                    return 1;
                }
            }

            return 1;
        }
    );

    # SUPER is wrapped in _execute_coderef alredy
    return $self->SUPER::_init_fs();
}

sub _execute_coderef {
    my ( $self, $coderef ) = @_;

    my $running_as_root = $> == 0;

    if ( $running_as_root && $self->{'user'} ne 'root' ) {
        if ( !$self->{'uid'} ) {
            ( $self->{'uid'}, $self->{'gid'} ) = ( Cpanel::PwCache::getpwnam( $self->{'user'} ) )[ 2, 3 ];
        }

        # We need to temporarily lift the quota here to avoid directories ending up with 0644 perms
        # if an account is overquota -- see CPANEL-38838 for details
        # NOTE: the quotas will get restored when $tempquota goes out of scope
        my $tempquota = Cpanel::Quota::Temp->new( user => $self->{user} );
        $tempquota->disable();

        return Cpanel::AccessIds::ReducedPrivileges::call_as_user( $coderef, $self->{'uid'}, $self->{'gid'} );
    }

    return $coderef->();
}

#----------------------------------------------------------------------
# Static, private

sub _get_locale {
    return $locale ||= Cpanel::Locale->get_handle();
}

sub _time {
    return time();
}

1;

__END__

=encoding utf-8

=head1 NAME

Cpanel::SSLStorage::User - Storage database for user-level SSL items.

=head1 DESCRIPTION

This subclass of Cpanel::SSLStorage extends the base class by storing a
“friendly_name” for each resource as well as storing CSRs.

=head1 SYNOPSIS

    use Cpanel::SSLStorage::User ();

    #Auto-detect the user based on $>.
    my ( $ok, $sslstorage ) = Cpanel::SSLStorage::User->new();
    die "$sslstorage\n" if !$ok;

    my $record;
    ( $ok, $record ) = $sslstorage->add_key( text => $some_key );
    die "$record\n" if !$ok;

    my $found;
    ( $ok, $found ) = $sslstorage->find_keys( text => $some_key );
    die "$found\n" if !$ok;

    my $msg;
    ( $ok, $msg ) = $sslstorage->set_key_friendly_name( $found->[0], 'I am a friendly key!' );

=head1 SUBROUTINES

=head2 new( user => $username )

Instantiate an object. To avoid throwing exceptions, this constructor expects to return
the two-argument format described in Cpanel::SSLStorage’s documentation.

This method accepts an optional C<user> parameter; this is only useful when calling as a
superuser since otherwise we force using $>.

Note the two-argument return.

=head2 expunge_expired_certificates()

This function checks for certificates that are in the userstore that expired longer than EXPUNGE_CERTIFICATES_AFTER_SECONDS
ago and removes them. On success, this function returns a two-arg return of ( 1, \@expired_ssl_certificates_removed ). On failure, ( 0, $err_message ).

=head2 add_(*)

=over

=item add_key( text => $text, friendly_name => $description )

=item add_certificate( text => $text, friendly_name => $description )

=item add_csr( text => $text, friendly_name => $description )

=back

The “text” argument is required. An optional C<friendly_name> may be passed in;
if one is not given, it will be constructed from the SSL resource.
Two-argument return.

=head2 set_(*)

=over

=item set_key_friendly_name( $key_id_or_record, $new_friendly_name )

=item set_certificate_friendly_name( $cert_id_or_record, $new_friendly_name )

=item set_csr_friendly_name( $csr_id_or_record, $new_friendly_name )

=back

These each accept a resource hash or ID as the first argument, then the
new C<friendly_name> as the second argument. Two-argument return.

=head2 Misc

=over

=item find_csrs( <search terms> )

=item get_csr_text( $csr_id_or_record )

=item remove_csr( id => $csr_id )

=item get_csr_path( $csr_id_or_record )

=back

These work similarly to the methods defined in Cpanel::SSLStorage for keys
and certificates. Note that C<get_csr_path> leaks the backend storage
abstraction.
