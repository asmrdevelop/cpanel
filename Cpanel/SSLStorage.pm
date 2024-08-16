package Cpanel::SSLStorage;

# cpanel - Cpanel/SSLStorage.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

#Not Cpanel::JSON -- see below.
use JSON::XS ();

use Try::Tiny;

use Cpanel::CachedDataStore                 ();
use Cpanel::Crypt::Algorithm                ();
use Cpanel::Crypt::Constants                ();
use Cpanel::Exception                       ();
use Cpanel::Fcntl                           ();
use Cpanel::FileUtils::Write                ();
use Cpanel::LoadFile                        ();
use Cpanel::LoadModule                      ();
use Cpanel::Locale                          ();
use Cpanel::Debug                           ();
use Cpanel::PwCache                         ();
use Cpanel::SSL::Utils                      ();
use Cpanel::SSLStorage::Utils               ();
use Cpanel::SSL::Objects::Certificate::File ();
use Cpanel::SV                              ();

our $EXPUNGE_CERTIFICATES_AFTER_SECONDS = 4 * 30 * 24 * 60**2;    # 4, 30 day periods (months) in seconds
our $CACHE_SUFFIX                       = '.cache';

my $MAIL_GID;

#NOTE: Do NOT instantiate this class directly;
#instead, instantiate one of its subclasses.

#TODO: Create different backends that implement this module's interface? e.g.:
#Cpanel::SSLStorage::File
#Cpanel::SSLStorage::SQLite
#Cpanel::SSLStorage::MySQL

#NOTE: This module refers to file contents as "text". This is different
#from OpenSSL's referring to "text"s as human-readable parses.
#
#For example, "openssl genrsa | openssl rsa -noout -text" will generate a key
#and then show a parse of its contents. This module, though, would regard the
#output of just "openssl genrsa" as the "text".

#NOTE: Most methods in this module and its subclasses presume list context
#and return thus: ( $status, $data_or_errmsg )

#CPANEL-12118, CPANEL-12179: Larger timeout for servers with high number of certs
my $SSL_STORAGE_LOCK_WAIT_TIME = 340;

#384 bits is actually horribly UN-safe, but we aren't sure which countries
#allow RSA keys with which strengths. So, this is a conservative safety-net.
my $MIN_SAFE_MODULUS_LENGTH = 384;

#Properties added after the initial rollout of this datastore:
my @LATER_CERTIFICATE_PROPERTIES = (
    'validation_type',
    'signature_algorithm',
    'key_algorithm',
    'ecdsa_curve_name',
    'ecdsa_public',
);

my @LATER_KEY_PROPERTIES = (
    'ecdsa_curve_name',
    'ecdsa_public',
);

#NOTE: Overridden in tests.
sub _BASE_DIRECTORY { return '/var/cpanel/ssl' }

sub _UNIQUES {
    return (

        # No reason to store the same key twice.
        # The colon notation means to concatenate the fields together
        # with a colon as separator, treating undef/empty as nonexistent.
        # Thus, RSA will compare modulus, and ECDSA will compare
        # $ecdsa_curve_name:$ecdsa_public
        #
        # This logic is now somewhat duplicated in _find() because
        # it’s too complex to try to create a declarative syntax
        # that requires both ECDSA parameters apart from modulus.
        key => ['modulus:ecdsa_curve_name:ecdsa_public'],
    );
}

#This does NOT include uniques.
sub _INDEXES {
    return (
        key => [],

        certificate => [
            'modulus',
            'ecdsa_curve_name',
            'ecdsa_public',

            # Certificates have a commonName for both issuer and subject.
            'subject.commonName',
        ],
    );
}

sub _EXTENSION {
    return (
        key         => 'key',
        certificate => 'crt',
    );
}

sub _DIRECTORY {
    return (
        key         => 'keys',
        certificate => 'certs',
    );
}

sub _MODE {
    return (
        key         => 0640,
        certificate => 0644,
    );
}

sub _FINDER {
    return (
        key         => 'find_keys',
        certificate => 'find_certificates',
    );
}

sub _TEXT {
    return (
        key         => 'get_key_text',
        certificate => 'get_certificate_text',
    );
}

sub _ADD {
    return (
        key         => 'add_key',
        certificate => 'add_certificate',
    );
}

sub _MAKE_ID {
    return (
        'key'         => \&Cpanel::SSLStorage::Utils::make_key_id,
        'certificate' => \&Cpanel::SSLStorage::Utils::make_certificate_id,
    );
}

my $DATASTORE_PERMS = 0600;

my $locale;

#Pass in a type.
sub _get_indexes_ar {
    my ( $self, $type ) = @_;
    return { $self->_INDEXES() }->{$type};
}

#Pass in a type.
sub _get_uniques_ar {
    my ( $self, $type ) = @_;
    return { $self->_UNIQUES() }->{$type} || [];
}

#Pass in a type.
sub _get_directory {
    my ( $self, $type ) = @_;
    return { $self->_DIRECTORY() }->{$type};
}

#Pass in a type.
sub _get_extension {
    my ( $self, $type ) = @_;
    return { $self->_EXTENSION() }->{$type};
}

#Pass in a type.
sub _get_mode {
    my ( $self, $type ) = @_;
    return { $self->_MODE() }->{$type};
}

sub find_keys {
    my ( $self, %query )   = @_;
    my ( $ok,   $keys_ar ) = $self->_find( %query, type => 'key' );

    if ( $ok && !$self->{'_disable_required_fields_check'} ) {
        $self->_ensure_keys_have_all_required_fields($keys_ar);
    }

    return ( $ok, $keys_ar );
}

sub find_certificates {
    my ( $self, %query ) = @_;

    my ( $ok, $certs_ar ) = $self->_find( %query, type => 'certificate' );

    if ( !$self->{'_disable_required_fields_check'} ) {
        $self->_ensure_certificates_have_all_required_fields($certs_ar) if $ok;
    }

    return ( $ok, $certs_ar );
}

sub _ensure_keys_have_all_required_fields ( $self, $recs_ar ) {

    for my $rec_hr (@$recs_ar) {
        $rec_hr->{$_} //= undef for @LATER_KEY_PROPERTIES;
    }

    return;
}

sub _ensure_certificates_have_all_required_fields {
    my ( $self, $certs_ar ) = @_;

    return $self->_execute_coderef(
        sub {
            #In 11.56 we added “validation_type”. This will put that in the response
            #for all records that predate this addition.
            for my $cert_ar (@$certs_ar) {
                next
                  if ( !grep { !exists $cert_ar->{$_} } @LATER_CERTIFICATE_PROPERTIES )
                  && $cert_ar->{'issuer_text'}
                  && $cert_ar->{'subject_text'};

                my $path = $self->get_certificate_path( $cert_ar->{'id'} );
                my $obj;
                local $@;
                eval { $obj = Cpanel::SSL::Objects::Certificate::File->new( 'path' => $path ); };
                if ($@) {
                    return ( 0, Cpanel::Exception::get_string($@) );
                }
                my $parse = $obj->parsed();

                $cert_ar->{'issuer_text'}  ||= $obj->{'issuer_text'};
                $cert_ar->{'subject_text'} ||= $obj->{'subject_text'};

                for (@LATER_CERTIFICATE_PROPERTIES) {
                    $cert_ar->{$_} ||= $parse->{$_};
                }
            }
            return 1;
        }
    );
}

sub get_key_path {
    my ( $self, $id ) = @_;
    return $self->_get_path( 'key', $id );
}

sub get_certificate_path {
    my ( $self, $id ) = @_;
    return $self->_get_path( 'certificate', $id );
}

sub get_key_text {
    my ( $self, $id_or_hr ) = @_;
    my ( $ok,   $text )     = $self->_get_text( 'key', $id_or_hr );

    if ( !$ok && !$text ) {
        my $id = ref($id_or_hr) ? $id_or_hr->{'id'} : $id_or_hr;

        _get_locale();
        $text = $locale->maketext( 'No key with the ID “[_1]” exists.', $id );
    }

    return ( $ok, $text );
}

sub get_certificate_text {
    my ( $self, $id_or_hr ) = @_;
    my ( $ok,   $text )     = $self->_get_text( 'certificate', $id_or_hr );

    if ( !$ok && !$text ) {
        my $id = ref($id_or_hr) ? $id_or_hr->{'id'} : $id_or_hr;

        _get_locale();
        $text = $locale->maketext( 'No certificate with ID “[_1]” exists.', $id );
    }

    return ( $ok, $text );
}

sub remove_key {
    my ( $self, %opts ) = @_;

    my $id = $opts{'id'};

    return $self->_remove_item(
        'id'   => $id,
        'type' => 'key',
    );
}

sub remove_certificate {
    my ( $self, %opts ) = @_;

    my $id = $opts{'id'};

    return $self->_remove_item(
        'id'   => $id,
        'type' => 'certificate',
    );
}

#----------------------------------------------------------------------
# Convenience

#Returns ( 0, $msg ) or ( 1, $payload ), where $payload is:
# [
#   { type: (type), data: (sslstorage data), text: (file contents) },
#   ...,
# ]
sub export {
    my ($self) = @_;

    my %finder      = $self->_FINDER();
    my %text_getter = $self->_TEXT();

    my @records;
    for my $type ( sort keys %finder ) {
        my $find_func     = $finder{$type};
        my $get_text_func = $text_getter{$type};

        #This would happen if we tried importing CA bundles into a user store,
        #or CSRs into an installed store.
        next if !$find_func || !$get_text_func;

        my ( $ok, $records ) = $self->$find_func();
        return ( 0, $records ) if !$ok;

        if (@$records) {
            for my $record (@$records) {
                my ( $ok, $text ) = $self->$get_text_func( $record->{'id'} );
                return ( 0, $text ) if !$ok;

                if ($text) {
                    push @records, { 'type' => $type, 'text' => $text, 'data' => $record };
                }
            }
        }
    }

    return ( 1, \@records );
}

#
# FIXME: TODO:
# *** import *** is a reserved function name
# We have a hack to check for ::BEGIN, however
# we should just change the name of this function
# in the future.
#
sub import {
    my ( $self, $records_ar ) = @_;

    return if !ref($self) && ( caller 1 )[3] =~ m<::BEGIN\z>;    #since use() will call import()

    my %adder = $self->_ADD();

    return $self->_execute_coderef(
        sub {
            my @new_records;

            #Lock for race safety.
            my ( $ok, $ds_data ) = $self->_load_datastore_rw();
            return ( 0, $ds_data ) if !$ok;

            for my $record (@$records_ar) {
                my $adder_func = $adder{ $record->{'type'} };

                my ( $ok, $rec ) = $self->$adder_func( $self->_build_import_options($record) );
                return ( 0, $rec ) if !$ok;

                push @new_records, { type => $record->{'type'}, data => $rec };
            }

            #Now do the real save.
            my ( $save_ok, $save_msg ) = $self->_save_datastore();
            return ( 0, $save_msg ) if !$save_ok;

            return ( 1, \@new_records );
        }
    );
}

#Rebuild the datastore from the filesystem, using the useful bits
#from the existing datastore (as the subclasses define).
#Parameters:
#   types: an array ref of types to check. Defaults to everything in _FINDER().
#Returns two values:
#   status (boolean)
#   err/payload
#...where "payload" is a list of:
#   { action:"add/remove", type:"...", path:"...", details:{...} }
sub rebuild_records {
    my ( $self, @args ) = @_;

    my @result = $self->_execute_coderef(
        sub {
            return $self->_rebuild_records(@args);
        }
    );
    return @result;
}

sub _rebuild_records {
    my ( $self, %OPTS ) = @_;

    #Wrap the rebuilds with an "_in_rebuild" property so that datastore
    #reads from within the rebuild won't trigger their own auto-rebuilds.
    local $self->{'_in_rebuild'} = 1;

    my %finder  = $self->_FINDER();
    my %adder   = $self->_ADD();
    my %make_id = $self->_MAKE_ID();

    my @types = $OPTS{'types'} ? @{ $OPTS{'types'} } : sort keys %finder;

    #Lock the old datastore file so that no other processes will mess with it
    #during the rebuild.
    my ( $ds_ok, $ds_data ) = $self->_load_datastore_rw();
    return ( 0, $ds_data ) if !$ds_ok;

    my %old_records;
    my %old_lookup;
    for my $type ( sort keys %finder ) {
        $old_lookup{$type}  = $ds_data->{'files'}{$type};
        $old_records{$type} = [ values %{ $old_lookup{$type} } ];
    }

    #Do NOT create a new hash here, or else we lose all changes below.
    %$ds_data = ();

    my @result;

    # We want the keys to be processed first, so that the modulus info
    # is populated by the time we get to parsing the certs/csrs.
    for my $type ( 'key', grep { $_ ne 'key' } @types ) {
        my $adder_name = $adder{$type};
        my $adder_cr   = $self->can($adder_name);
        die "$self cannot '$adder_name'!\n" if !$adder_cr;

        #Need to queue up the things to add, then remove first, then add.
        my @items_to_add;

        my %ids_to_keep;

        my $dir = $self->{'_path'} . '/' . $self->_get_directory($type);
        next if !-d $dir;    #It's ok if the directory doesn't exist.

        opendir( my $dfh, $dir ) or do {
            $self->_unlock_datastore();

            _get_locale();
            return ( 0, $locale->maketext( 'The rebuild failed because the system could not open the directory “[_1]” because of an error: [_2]', $dir, $! ) );
        };
        while ( my $node = readdir $dfh ) {
            next if $node eq '.' || $node eq '..';
            next if !-f "$dir/$node";

            #Would it be better just to ignore a file that can't be read?
            local $!;
            my $contents_r = Cpanel::LoadFile::loadfile_r("$dir/$node");
            if ($!) {
                $self->_unlock_datastore();

                _get_locale();
                return ( 0, $locale->maketext( 'The rebuild failed because the system could not open the file “[_1]” because of an error: [_2]', "$dir/$node" ) );
            }

            my ( $valid, $id ) = $make_id{$type}->($$contents_r);
            next if !$valid;    #Wasn't a valid resource of type $type.

            #We've already seen this one, so don't add it a second time.
            #NOTE: This means that there are multiple copies of the same
            #item on the disk. We may not be getting the one that the user wants,
            #but there's no good way to distinguish.
            next if exists $ids_to_keep{$id};

            my %extra_params = $self->_repair_extra_add_parameters( type => $type, text => $contents_r, path => "$dir/$node", existing => $old_lookup{$type}{$id}, old_records => \%old_records, );
            next if $extra_params{'skip'};

            $ids_to_keep{$id} = undef;

            push @items_to_add, {
                id       => $id,
                existing => $old_lookup{$type}{$id} ? 1 : 0,
                text     => $$contents_r,
                created  => $old_lookup{$type}{$id} ? $old_lookup{$type}{$id}{'created'} : ( stat "$dir/$node" )[10],
                path     => "$dir/$node",

                # created might get overwritten from extra params if we find
                # an old format item (this is expected)
                %extra_params,
            };
        }
        closedir $dfh;

        for my $item (@items_to_add) {
            my ( $ok, $new ) = $adder_cr->( $self, %$item );
            return ( 0, $new ) if !$ok;

            #Should this include the text?
            if ( !$item->{'existing'} ) {
                push @result,
                  {
                    action  => 'add',
                    type    => $type,
                    path    => $item->{'path'},
                    details => $new,
                  };
            }
        }

        my %lookup_copy = %{ $old_lookup{$type} };
        delete @lookup_copy{ map { $_->{'id'} } @items_to_add };
        push @result, map { { action => 'remove', type => $type, path => undef, details => $_, } } values %lookup_copy;
    }

    my ( $move_ok, $move_err ) = $self->_copy_old_records_for_rebuild();
    return ( 0, $move_err ) if !$move_ok;

    #Write the new file.
    my ( $save_ok, $save_msg ) = $self->_save_datastore();
    return ( 0, $save_msg ) if !$save_ok;

    return ( 1, \@result );
}

#Saving: with the file lock from _load_datastore_rw(), we now read in the
#old contents. If, and only if, there was something there, we:
#1) Determine a a new $backup_ds_file to copy the old datastore into.
#2) Write the old datastore into $backup_ds_file.
#3) Save the new datastore.
#NOTE: We have to read in the file contents directly since the original
#datastore could be corrupt.
sub _copy_old_records_for_rebuild {
    my ($self) = @_;

    local $!;

    my $ds_file    = $self->_datastore_file();
    my $ds_lock_fh = $self->{'_locked_ds'}->fh();

    if ( !$ds_lock_fh ) {
        _get_locale();
        return ( 0, $locale->maketext( 'The rebuild failed because the system could not open the datastore file “[_1]”.', $ds_file ) );
    }

    seek( $ds_lock_fh, 0, 0 ) or do {
        my $err = $!;
        $self->_unlock_datastore();

        #It's a very esoteric error message, but the user should never see this anyway.
        _get_locale();
        return ( 0, $locale->maketext( 'The rebuild failed because the system could not rewind the file pointer for “[_1]” because of an error: [_2]', $ds_file, $err ) );
    };

    my $old_stuff = do { local $/; readline $ds_lock_fh };
    if ($!) {    #Shouldn't happen, but hey.
        my $err = $!;
        $self->_unlock_datastore();

        _get_locale();
        return ( 0, $locale->maketext( 'The rebuild failed because the system could not read the file “[_1]” because of an error: [_2]', $ds_file, $err ) );
    }

    #If there was nothing there before, don't create the backup file.
    return 1 if !length $old_stuff;

    my ( $backup_ds_file, $backup_ds_fh );
    $backup_ds_file = $ds_file . '.' . time() . '.0';
    {
        my $orig_umask = umask( $DATASTORE_PERMS ^ 07777 );
        my $attempts   = 0;
        while ( !$backup_ds_file
            || ( ++$attempts < 64 && !sysopen( $backup_ds_fh, $backup_ds_file, Cpanel::Fcntl::or_flags(qw( O_WRONLY O_EXCL O_CREAT )), 00777 ) ) ) {

            $backup_ds_fh   = undef;
            $backup_ds_file = $ds_file . '.' . time() . '.' . rand(9999999);
            Cpanel::SV::untaint($backup_ds_file);
        }
        umask($orig_umask) if defined $orig_umask;
    }

    if ( !$backup_ds_fh ) {
        $self->_unlock_datastore();

        _get_locale();
        return ( 0, $locale->maketext( 'The rebuild failed because the system could not create the file “[_1]” because of an unknown error.', $backup_ds_file ) );
    }

    my ( $write_ok, $write_msg ) = $self->_execute_coderef(
        sub {
            # Do this or writefile() gives warnings about printing undef.
            my $to_print = $old_stuff // '';
            Cpanel::FileUtils::Write::overwrite_no_exceptions( $backup_ds_file, $to_print, $DATASTORE_PERMS ) or do {
                _get_locale();
                return ( 0, $locale->maketext( 'The rebuild failed because the system could not write the file “[_1]” because of an error: [_2]', $backup_ds_file, $! ) );
            };

            Cpanel::Debug::log_info("The SSLStorage file formerly at $ds_file is now backed up at $backup_ds_file.");

            return 1;
        }
    );

    return $write_ok ? (1) : ( 0, $write_msg );
}

sub find_key_for_domain {
    my ( $self, $domain ) = @_;

    my ( $ok, $certs ) = $self->find_certificates( 'subject.commonName' => $domain );
    return ( 0, $certs ) if !$ok;

    if ( $certs && @$certs ) {
        for my $c ( sort { $b->{'not_after'} <=> $a->{'not_after'} } @$certs ) {
            my @params = $self->_get_key_match_params($c);

            my ( $ok, $keys ) = $self->find_keys(@params);

            if ( $ok && $keys && @$keys ) {
                return ( 1, $keys->[0] );
            }
        }
    }

    return ( 1, undef );
}

sub find_key_for_object ( $self, $matchee ) {

    local $@;
    my @terms_kv = Cpanel::Crypt::Algorithm::dispatch_from_object(
        $matchee,
        rsa   => sub { 'modulus' },
        ecdsa => sub { 'ecdsa_curve_name', 'ecdsa_public' },
    );

    @terms_kv = map { $_ => $matchee->$_() } @terms_kv;

    my ( $ok, $keys ) = $self->find_keys(@terms_kv);
    return ( $ok, $ok ? $keys->[0] : $keys );
}

sub _get_key_match_params ( $, $parsed_hr ) {
    my @params;

    Cpanel::Crypt::Algorithm::dispatch_from_parse(
        $parsed_hr,
        rsa => sub {
            @params = %{$parsed_hr}{'modulus'};
        },
        ecdsa => sub {
            @params = %{$parsed_hr}{ 'ecdsa_curve_name', 'ecdsa_public' };
        },
    );

    return @params;
}

sub add_key_and_certificate_if_needed {
    my ( $self, %opts ) = @_;

    my $write_coderef = sub {
        return $self->_add_key_and_certificate_if_needed(%opts);
    };

    return $self->_execute_coderef($write_coderef);
}

sub _add_key_and_certificate_if_needed {
    my ( $self, %opts ) = @_;

    my ( $key_text, $key_friendly_name, $cert_text, $cert_friendly_name ) = @opts{qw( key key_friendly_name cert cert_friendly_name )};

    my ( $ok, $message ) = $self->_load_datastore_rw();
    return ( 0, $message ) if !$ok;

    ( $ok, my $key_record ) = $self->_build_key_record( %opts, text => $key_text, friendly_name => $key_friendly_name );
    if ( !$ok ) {
        $self->_unlock_datastore();
        return ( 0, $key_record );
    }

    ( $ok, $message ) = $self->_add_key_record( $key_record, $key_text );
    if ( !$ok ) {
        if ( !ref $message || $$message !~ m/already_used/ ) {
            $self->_unlock_datastore();
            return ( 0, ref $message ? $$message : $message );
        }
    }

    ( $ok, my $cert_record ) = $self->_build_certificate_record( %opts, text => $cert_text, friendly_name => $cert_friendly_name );
    if ( !$ok ) {
        $self->_unlock_datastore();
        return ( 0, $cert_record );
    }

    ( $ok, $message ) = $self->_add_certificate_record( $cert_record, $cert_text );
    if ( !$ok ) {
        if ( !ref $message || $$message !~ m/already_used/ ) {
            $self->_unlock_datastore();
            return ( 0, ref $message ? $$message : $message );
        }
    }

    ( $ok, $message ) = $self->_save_datastore();
    if ( !$ok ) {
        $self->_unlock_datastore();
        return ( 0, $message );
    }

    return ( 1, { key_record => $key_record, certificate_record => $cert_record } );
}

#TODO: Remove this from the base class and put it in Installed.pm?
#It's only being used there.
sub remove_certificate_and_key {
    my ( $self, %opts ) = @_;

    my $id = $opts{'id'};
    my ( $ok, $certs_ar ) = $self->find_certificates( 'id' => $id );
    return ( 0, $certs_ar ) if !$ok;
    return 1                if !@$certs_ar;

    my $write_coderef = sub {

        #Hold the lock here so that all of the remove_* operations
        #happen with the same load of the data.
        ( $ok, my $msg ) = $self->_load_datastore_rw();
        return ( 0, $msg ) if !$ok;

        ( $ok, $msg ) = $self->remove_certificate( 'id' => $id );
        if ( !$ok ) {
            $self->_unlock_datastore();
            return ( 0, $msg );
        }

        my @search_params = $self->_get_key_match_params( $certs_ar->[0] );

        #As long as no other certificate has the same modulus, delete the key.
        ( $ok, my $modulus_certs ) = $self->find_certificates(
            @search_params,
        );
        if ( $ok && $modulus_certs && !@$modulus_certs ) {
            my ( $ok, $keys_ar ) = $self->find_keys(@search_params);
            if ($ok) {
                for my $key (@$keys_ar) {
                    my ( $ok, $msg ) = $self->remove_key( 'id' => $key->{'id'} );
                    if ( !$ok ) {
                        _get_locale();
                        return ( 0, $locale->maketext( 'An error occurred while deleting the key with ID “[_1]”: [_2]', $key->{'id'}, $msg ) );
                    }
                }
            }
        }

        #Now let’s save the data.
        return $self->_save_datastore();
    };

    return $self->_execute_coderef($write_coderef);
}

#----------------------------------------------------------------------
# PRIVATE

#For testing purposes, the filesystem part of instantiating this object is
#done as a separate function, _init_fs().
#
#Since it is not typical for a constructor function to return anything but an
#object, this constructor will respond to both scalar and list contexts:
#   scalar : Returns the object, or undef if an error.
#   list   : Returns ( 1, $object ) or ( 0, $error ).
sub _init {
    my ( $self, %opts ) = @_;

    $self->{'_disable_required_fields_check'} = delete $opts{'disable_required_fields_check'};

    my ( $ok, $err ) = $self->_init_fs();

    if (wantarray) {
        return $ok ? ( 1, $self ) : ( 0, $err );
    }

    $self->{'_times_loaded_rw'} = 0;

    return $ok ? $self : undef;
}

sub _build_key_record {
    my ( $self, %OPTS ) = @_;

    # parse_key_text already calls get_key_from_text so no need to
    # do it twice
    my ( $ok, $parse ) = Cpanel::SSL::Utils::parse_key_text( $OPTS{'text'} );
    return ( 0, $parse ) if !$ok;

    my %key_parts;

    my $err;

    Cpanel::Crypt::Algorithm::dispatch_from_parse(
        $parse,
        rsa => sub {
            my $modulus_length = Cpanel::SSL::Utils::hex_modulus_length( $parse->{'modulus'} );
            if ( $modulus_length < $MIN_SAFE_MODULUS_LENGTH ) {
                _get_locale();
                $err = $locale->maketext( "An [asis,RSA] key’s modulus [output,strong,must] be a minimum of [quant,_1,bit,bits] long. This key’s modulus is only [quant,_2,bit,bits] long.", $MIN_SAFE_MODULUS_LENGTH, $modulus_length );
            }
            else {
                @key_parts{ 'modulus', 'modulus_length' } = (
                    $parse->{'modulus'},
                    $modulus_length,
                );
            }
        },
        ecdsa => sub {
            my @names = ( 'ecdsa_curve_name', 'ecdsa_public' );
            @key_parts{@names} = @{$parse}{@names};
        },
    );

    return ( 0, $err ) if $err;

    my $id;
    ( $ok, $id ) = Cpanel::SSLStorage::Utils::make_key_id($parse);
    return ( 0, $id ) if !$ok;

    my $new_record = {
        'id'          => $id,
        'created'     => $OPTS{'created'},
        key_algorithm => $parse->{'key_algorithm'},
        %key_parts{
            'modulus',          'modulus_length',
            'ecdsa_curve_name', 'ecdsa_public',
        },
    };

    return $self->_initialize_new_record( 'key', $new_record, \%OPTS );
}

sub _add_key_record {
    my ( $self, $new_record, $text ) = @_;

    return $self->_save_new(
        'record' => $new_record,
        'type'   => 'key',
        'text'   => $text,
    );
}

#options:
#   text (required) - the certificate's PEM text
#   created (optional) - the creation time
sub _build_certificate_record {
    my ( $self, %OPTS ) = @_;

    my ( $ok, $cert ) = Cpanel::SSL::Utils::get_certificate_from_text( $OPTS{'text'} );
    return ( 0, $cert ) if !$ok;

    ( $ok, my $parse ) = Cpanel::SSL::Utils::parse_certificate_text($cert);
    return ( 0, $parse ) if !$ok;

    my @key_parts;

    my $err;

    Cpanel::Crypt::Algorithm::dispatch_from_parse(
        $parse,
        rsa => sub {
            my $modulus_length = Cpanel::SSL::Utils::hex_modulus_length( $parse->{'modulus'} );
            if ( $modulus_length < $MIN_SAFE_MODULUS_LENGTH ) {
                _get_locale();
                $err = $locale->maketext( "A certificate’s modulus must be a minimum of [quant,_1,bit,bits] long. This certificate’s modulus is only [quant,_2,bit,bits] long.", $MIN_SAFE_MODULUS_LENGTH, $modulus_length );
            }
            else {
                push @key_parts, (
                    modulus        => $parse->{'modulus'},
                    modulus_length => $modulus_length,
                );
            }
        },
        ecdsa => sub {
            push @key_parts, %{$parse}{ 'ecdsa_curve_name', 'ecdsa_public' };
        },
    );

    return ( 0, $err ) if $err;

    my $id;
    ( $ok, $id ) = Cpanel::SSLStorage::Utils::make_certificate_id( $cert, $parse );
    return ( 0, $id ) if !$ok;

    my $new_record = {
        'id' => $id,

        'not_before' => $parse->{'not_before'},
        'not_after'  => $parse->{'not_after'},

        'subject.commonName'      => $parse->{'subject'}{'commonName'},
        'issuer.commonName'       => $parse->{'issuer'}{'commonName'},
        'issuer.organizationName' => $parse->{'issuer'}{'organizationName'},
        'serial'                  => $parse->{'serial'},

        'domains'        => $parse->{'domains'},
        'is_self_signed' => $parse->{'is_self_signed'},

        'created' => $OPTS{'created'},

        @key_parts,

        ( map { $_ => $parse->{$_} } @LATER_CERTIFICATE_PROPERTIES ),
    };

    return $self->_initialize_new_record( 'certificate', $new_record, \%OPTS );
}

sub _add_certificate_record {
    my ( $self, $new_record, $text ) = @_;

    return $self->_save_new(
        'record' => $new_record,
        'type'   => 'certificate',
        'text'   => $text,
    );
}

sub _get_path {
    my ( $self, $type, $id ) = @_;

    if ( 'HASH' eq ref $id ) {
        $id = $id->{'id'};
    }

    my $dir = $self->{'_get_directory'}{$type} ||= $self->_get_directory($type);
    my $ext = $self->{'_get_extension'}{$type} ||= $self->_get_extension($type);

    #So this code path can be called statically.
    my $base = $self->{'_path'} || _BASE_DIRECTORY();

    return "$base/$dir/$id.$ext";
}

sub _init_fs {
    my ($self) = @_;

    return $self->_execute_coderef(
        sub {
            my $path = $self->{'_path'};

            my @needed_paths = grep { !-e $_ } map { "$path/$_" } values %{ { $self->_DIRECTORY() } };
            if (@needed_paths) {
                if ( !-d $path && !mkdir( $path, 0755 ) ) {
                    my $err = $!;
                    return _mkdir_error( $path, Cpanel::PwCache::getusername(), $err );
                }
                foreach my $subpath (@needed_paths) {
                    if ( !( mkdir $subpath, 0751 and _chown_if_needed($subpath) ) ) {
                        my $err = $!;
                        return _mkdir_error( $subpath, Cpanel::PwCache::getusername(), $err );
                    }
                }
            }

            #Might as well make sure there's a datastore file so that
            #a read-only loaddatastore() on that file doesn't error back.
            if ( !-f $self->_datastore_file() ) {
                $self->{'_file_did_not_exist'} = 1;
                my $ok = sysopen( my $fh, $self->_datastore_file(), Cpanel::Fcntl::or_flags(qw( O_WRONLY O_CREAT )), $DATASTORE_PERMS );
                if ( !$ok ) {
                    my $err = $!;
                    _get_locale();
                    return ( 0, $locale->maketext( 'An error prevented the creation of the SSL datastore: [_1]', $err ) );
                }
            }

            Cpanel::CachedDataStore::clear_one_cache( $self->_datastore_file() ) if $self->{'clear_cache'};

            return 1;
        }
    );
}

sub _chown_if_needed {
    my $path = shift;
    if ( $> == 0 ) {
        chown 0, ( $MAIL_GID ||= ( Cpanel::PwCache::getpwnam('mail') )[3] ), $path or return;
    }
    return 1;
}

#If the error message is undef, the path doesn't exist;
#i.e., the resource isn't there.
sub _get_text {
    my ( $self, $type, $id ) = @_;

    if ( ref $id ) {
        $id = $id->{'id'};
    }

    #Make sure the ID is valid before we go to the filesystem.
    if ( $id !~ tr{/}{} && $id !~ m{\A\.\.?\z} ) {
        my $path = $self->_get_path( $type, $id );
        my $text = $self->_execute_coderef(
            sub {
                return Cpanel::LoadFile::loadfile($path);
            }
        );

        if ( !$text ) {
            return if !-r $path || !-f _;
            return _read_error( $path, Cpanel::PwCache::getusername(), $! );
        }

        return ( 1, $text );
    }

    return;
}

# e.g., if my index is foo:bar, then join $source->{foo} and
# $source->{bar} with a colon, weeding out empty values.
sub _create_colon_aware_index_value ( $source, $index ) {

    # NB: A direct grep on the hash slice would (surprisingly?) autovivify
    # the values in %$source. That would break things, so let’s avoid it.
    my @values = @{$source}{ split m<:>, $index };

    return join( ':', grep { length } @values );
}

# e.g., if my index is foo:bar, then delete
# $source->{foo} and $source->{bar}.
sub _delete_entries_for_colon_aware_index ( $source, $index ) {
    delete @{$source}{ split m<:>, $index };

    return;
}

sub __find_in_unique ( $self, $ds_data, $type, $query_hr ) {    ## no critic qw(ProhibitManyArgs)
    my $records_by_id_hr = $ds_data->{'files'}{$type};

    my $ds_uniques = $ds_data->{'uniques'}{$type};

    my @results;

  UNIQUE:
    for my $unique ( @{ $self->_get_uniques_ar($type) } ) {

        my $query_value;

        # Searches on RSA modulus or ECDSA curve parameters are
        # “special” because it’s a bit too complex to try to
        # notate declaratively how this works.
        if ( 0 == rindex( $unique, 'modulus', 0 ) ) {
            my $query_is_ecc = length $query_hr->{'ecdsa_curve_name'} || length $query_hr->{'ecdsa_public'};

            if ( $query_value = $query_hr->{'modulus'} ) {
                die 'Can’t search RSA & ECDSA concurrently!' if $query_is_ecc;
            }
            elsif ($query_is_ecc) {
                next UNIQUE if !length $query_hr->{'ecdsa_curve_name'};
                next UNIQUE if !length $query_hr->{'ecdsa_public'};
            }
            else {
                next UNIQUE;
            }

            $query_value = _create_colon_aware_index_value( $query_hr, $unique );
        }
        else {
            $query_value = $query_hr->{$unique};
        }

        if ( length $query_value && !@results ) {
            my $id = $ds_uniques->{$unique}{$query_value};

            return [] if !$id;

            #As with querying on the ID, we're not done yet.
            push @results, $records_by_id_hr->{$id};

            _delete_entries_for_colon_aware_index( $query_hr, $unique );
        }
    }

    return @results ? \@results : undef;
}

#Hard-coded query terms are:
#   type
#   id
#
#Generally, %query is something like:
#   type => 'key',
#   owner => 'theuser',
#   modulus => 'a443df8912121217dd...',
#
#Additionally, a "text" query may be passed in.
sub _find {
    my ( $self, %query ) = @_;

    my $type = delete $query{'type'};
    if ( ( !exists $query{'id'} ) && exists $query{'text'} ) {
        if ( !length $query{'text'} ) {
            return ( 0, "query text was empty" );
        }

        my ( $ok, $id ) = { $self->_MAKE_ID() }->{$type}->( $query{'text'} );
        return ( 0, $id ) if !$ok;

        $query{'id'} = $id;
        delete $query{'text'};
    }

    my ( $ok, $ds_data ) = $self->_execute_coderef(
        sub {
            # Prevent double cloning since
            # we will always clone our find
            # results at the end of this function
            return $self->_load_datastore_ro( 'no_clone' => 1 );
        }
    );
    return ( 0, $ds_data ) if !$ok;

    my $records_by_id_hr = $ds_data->{'files'}{$type};
    return ( 1, [] ) if !$records_by_id_hr || !%$records_by_id_hr;

    my $ds_indexes = $ds_data->{'indexes'}{$type};
    my $ds_uniques = $ds_data->{'uniques'}{$type};

    my @results;

    #Our "base" query can work one of these ways, in order of
    #preference:
    #1) By grabbing the one record with the ID.
    #2) By grabbing the one record that matches a unique field.
    #3) By grabbing the records that match an indexed field.
    #4) By grabbing all records.
    #
    #Once we have the "base", we filter out by the remaining
    #filter terms.

    #1) See if we queried on an ID.
    if ( defined $query{'id'} ) {
        my $record = $records_by_id_hr->{ $query{'id'} };
        return ( 1, [] ) if !$record;

        #We're not done here since a later query term might kill this one,
        #meaning we'll return an empty set.
        push @results, $record;
        delete $query{'id'};
    }

    #2) No ID, so check other unique fields.
    if ( !@results ) {
        my $results_ar = $self->__find_in_unique( $ds_data, $type, \%query );

        if ($results_ar) {
            return ( 1, [] ) if !@$results_ar;

            push @results, @$results_ar;
        }
    }

    #3) Still nothing? Check the indexes.
    if ( !@results ) {
        for my $index ( @{ $self->_get_indexes_ar($type) } ) {
            my $query_value = $query{$index};
            if ( length $query_value && !@results ) {
                my $ids_hr = $ds_indexes->{$index}{$query_value};

                if ($ids_hr) {
                    push @results, map { $records_by_id_hr->{$_} } keys %$ids_hr;
                }

                return ( 1, [] ) if !@results;

                delete $query{$index};
            }
        }
    }

    #4) Ok, just grab everything. Either we're filtering on something that's
    #not indexed/unique/primary, or we're not filtering at all.
    if ( !@results ) {
        @results = values %{$records_by_id_hr};
    }

    if ( scalar keys %query ) {

        #Each record in the result set must match each query term.
        #NOTE: Invalid query terms here will result in an empty return set!
        for my $term ( sort keys %query ) {
            next if !defined $query{$term};

            my $ds_value;
            @results = grep {
                $ds_value = $_->{$term};
                defined $ds_value
                  && (
                      ( 'HASH' eq ref $ds_value )  ? exists( $ds_value->{ $query{$term} } )
                    : ( 'ARRAY' eq ref $ds_value ) ? ( grep { $_ eq $query{$term} } @$ds_value )
                    :                                ( $ds_value eq $query{$term} )
                  )
            } @results;
        }
    }

    # We were sorting hashrefs before
    # so the sorting was removed as it
    # did not offer any value
    return (
        1,
        [
            map {
                my %copy = (

                    # A default for pre-v92 datastores:
                    key_algorithm => Cpanel::Crypt::Constants::ALGORITHM_RSA,

                    %{$_},
                );

                \%copy;
            } @results
        ]
    );
}

#This will return a string reference from a unique index conflict:
#   already_used <field_name> <id>
sub _save_new {
    my ( $self, %OPTS ) = @_;

    my ( $record, $type, $text ) = @OPTS{qw(record type text)};

    $text = Cpanel::SSL::Utils::demunge_ssldata($text);

    if ( $record->{'created'} && $record->{'created'} =~ m{[^0-9]} ) {
        _get_locale();
        return ( 0, $locale->maketext( '“[_1]” is not a valid value for “[_2]”.', $record->{'created'}, 'created' ) );
    }

    my $id   = $record->{'id'};
    my $mode = $self->_get_mode($type);
    my $path = $self->_get_path( $type, $id );

    return $self->_execute_coderef(
        sub {
            return $self->__save_new( record => $record, type => $type, text => $text, id => $id, mode => $mode, path => $path );
        }
    );
}

sub __save_new {
    my ( $self, %OPTS ) = @_;

    my ( $record, $type, $text, $id, $mode, $path ) = @OPTS{qw( record type text id mode path )};

    my ( $ok, $ds_data ) = $self->_load_datastore_rw();
    return ( 0, $ds_data ) if !$ok;

    #If all the uniques below match up with the pre-existing, then we
    #re-save the resource. This rebuilds the datastore entry.
    my $preexisting = $ds_data->{'files'}{$type}{$id};

    for my $unique ( @{ $self->_get_uniques_ar($type) } ) {
        my $new_value = _create_colon_aware_index_value( $record, $unique );

        if ($preexisting) {
            my $old_value = _create_colon_aware_index_value( $preexisting, $unique );
            if ( $old_value ne $new_value ) {
                my ( $ok, $unlocked ) = $self->_unlock_datastore();
                Cpanel::Debug::log_warn($unlocked) if !$ok;
                return ( 0, \"already_used id $id" );
            }
        }

        my $already_using = $ds_data->{'uniques'}{$type}{$unique}{$new_value};

        next if $already_using && $already_using eq $id;

        if ( defined $already_using ) {
            if ( exists $ds_data->{'files'}{$type}{$already_using} ) {
                my ( $ok, $unlocked ) = $self->_unlock_datastore();
                Cpanel::Debug::log_warn($unlocked) if !$ok;
                return ( 0, \"already_used $unique $already_using" );
            }
            else {
                Cpanel::Debug::log_warn( "SSL DATASTORE CORRUPTION DETECTED! Overwriting orphaned \"unique\" entry for $type with ID $already_using in " . $self->_datastore_file() );
            }
        }

        $ds_data->{'uniques'}{$type}{$unique}{$new_value} = $id;
    }
    if ( !( Cpanel::FileUtils::Write::overwrite_no_exceptions( $path, $text, $mode // 0644 ) and _chown_if_needed($path) ) ) {
        $self->_unlock_datastore();
        return _write_error( $path, Cpanel::PwCache::getusername(), $! );
    }

    $ds_data->{'files'}{$type}{$id} = $record;

    for my $index ( @{ $self->_get_indexes_ar($type) } ) {
        my $new_value = _create_colon_aware_index_value( $record, $index );
        next if !length $new_value;

        $ds_data->{'indexes'}{$type}{$index}{$new_value}{$id} = undef;
    }

    $record->{'created'} ||= $preexisting ? $preexisting->{'created'} : time;

    ( $ok, my $msg ) = $self->_save_datastore();

    # Clone was causing random crashes and since we only use user sslstorage
    # we aren't concerned about returning the reference during an
    # add function anymore so a top level clone is good enough.
    return $ok ? ( 1, {%$record} ) : ( 0, $msg );
}

#NOTE: This function's error messages are either scalars or scalar references.
#Scalar references function like error codes; the calling function is expected
#to prepare a suitable human-readable message.
#   id_not_found: No record with that type and ID exists.
#   already_used <field_name> <id>: Another record with ID <id> is already using the given value for <field_name>.
#
#This is done so that calling functions can form complete phrases; otherwise,
#we would have "certificate", "key", etc. literally appearing within
#otherwise-localized error messages.
sub _update_item {
    my ( $self, $type, $id, %new_attrs ) = @_;

    my $write_coderef = sub {
        my ( $ok, $ds_data ) = $self->_load_datastore_rw();
        return ( 0, $ds_data ) if !$ok;

        my $record = $ds_data->{'files'}{$type}{$id};
        if ( !$record ) {
            $self->_unlock_datastore();
            return ( 0, \"id_not_found" );
        }

        #Check for implementor errors.
        while ( my ( $key, $val ) = each %new_attrs ) {
            die "Invalid field in a $type: $key" if !exists $record->{$key};
        }

        #Update the unique indexes.
        my $ds_uniques = $ds_data->{'uniques'}{$type};

        for my $unique ( @{ $self->_get_uniques_ar($type) } ) {
            my $new_value = _create_colon_aware_index_value( \%new_attrs, $unique );
            next if !length $new_value;

            if ( my $already_using_id = $ds_uniques->{$unique}{$new_value} ) {
                $self->_unlock_datastore();

                #This "update" was to the same value that's in place.
                if ( $already_using_id eq $id ) {
                    return 1;
                }

                return ( 0, \"already_used $unique $already_using_id" );
            }
            else {
                my $old_value = _create_colon_aware_index_value( $record, $unique );
                delete $ds_uniques->{$unique}{$old_value};
                $ds_uniques->{$unique}{$new_value} = $id;
            }
        }

        # Update non-unique indexes.
        my $ds_indexes = $ds_data->{'indexes'}{$type};

        for my $index ( @{ $self->_get_indexes_ar($type) } ) {
            my $new_value = _create_colon_aware_index_value( \%new_attrs, $index );
            next if !length $new_value;

            my $old_value = _create_colon_aware_index_value( $record, $index );

            #Delete the old index entry.
            delete $ds_indexes->{$index}{$old_value}{$id};

            #Clean out the value's index entry if it's empty now.
            if ( !%{ $ds_indexes->{$index}{$old_value} } ) {
                delete $ds_indexes->{$index}{$old_value};
            }

            #Set the new index entry.
            $ds_indexes->{$index}{$new_value}{$id} = undef;
        }

        #Update the record itself.
        @{$record}{ keys %new_attrs } = values %new_attrs;

        return $self->_save_datastore();
    };

    return $self->_execute_coderef($write_coderef);
}

sub _remove_item {
    my ( $self, %OPTS ) = @_;

    my ( $id, $type ) = @OPTS{ 'id', 'type' };

    if ( ref $id ) {
        $id = $id->{'id'};
    }

    my $path = $self->_get_path( $type, $id );

    my $write_coderef = sub {
        return $self->__remove_item( id => $id, type => $type, path => $path );
    };

    return $self->_execute_coderef($write_coderef);
}

sub __remove_item {
    my ( $self, %OPTS ) = @_;

    my ( $id, $type, $path ) = @OPTS{qw( id type path )};

    if ( -f $path ) {
        unlink($path) or return _unlink_error( $path, Cpanel::PwCache::getusername(), $! );
    }

    if ( -f "$path$CACHE_SUFFIX" ) {
        unlink("$path$CACHE_SUFFIX") or return _unlink_error( "$path$CACHE_SUFFIX", Cpanel::PwCache::getusername(), $! );
    }

    my ( $ok, $ds_data ) = $self->_load_datastore_rw();
    return ( 0, $ds_data ) if !$ok;

    my $record = delete $ds_data->{'files'}{$type}{$id};

    my $ds_indexes = $ds_data->{'indexes'}{$type};

    #Clean out the uniques.
    for my $unique ( @{ $self->_get_uniques_ar($type) } ) {
        my $value = _create_colon_aware_index_value( $record, $unique );
        next if !length $value;

        delete $ds_data->{'uniques'}{$type}{$unique}{$value};
    }

    #Clean out the indexes.
    for my $index ( @{ $self->_get_indexes_ar($type) } ) {
        my $value = _create_colon_aware_index_value( $record, $index );
        next if !length $value;

        my $same_value_hr = $ds_indexes->{$index}{$value};

        delete $same_value_hr->{$id};

        #If no other record has that value, then clear it out.
        #
        #NB: Leave in place the hashes for index fields and types,
        #since there's little gained from removing them.
        if ( !%{$same_value_hr} ) {
            delete $ds_indexes->{$index}{$value};
        }
    }

    return $self->_save_datastore();
}

sub _datastore_file {
    my $self = shift;
    return $self->{'_path'} . '/ssl.db';
}

sub _mkdir_error {
    my ( $path, $user, $err ) = @_;

    _get_locale();
    return ( 0, $locale->maketext( 'The system failed to create the directory “[_1]” as the user “[_2]” because of an error: [_3]', $path, $user, $err ) );
}

sub _unlink_error {
    my ( $path, $user, $err ) = @_;

    _get_locale();
    return ( 0, $locale->maketext( 'The system failed to delete the file “[_1]” as the user “[_2]” because of an error: [_3]', $path, $user, $err ) );
}

sub _read_error {
    my ( $path, $user, $err ) = @_;

    _get_locale();
    return ( 0, $locale->maketext( 'The system failed to read the file “[_1]” as the user “[_2]” because of an error: [_3]', $path, $user, $err ) );
}

sub _write_error {
    my ( $path, $user, $err ) = @_;

    _get_locale();
    return ( 0, $locale->maketext( 'The system failed to write to the file “[_1]” as the user “[_2]” because of an error: [_3]', $path, $user, $err ) );
}

sub _migrate_datastore ( $self, $ds ) {

    my $data_uniques = $ds->{'data'} && $ds->{'data'}{'uniques'};
    my $key_uniques  = $data_uniques && $data_uniques->{'key'};
    if ( $key_uniques && $key_uniques->{'modulus'} ) {

        my %uniques         = $self->_UNIQUES();
        my $v92_replacement = $uniques{'key'}->[0];

        my $path = $self->_datastore_file();

        $key_uniques->{$v92_replacement} = delete $key_uniques->{'modulus'};
    }

    return;
}

sub _load_datastore {
    my ( $self, %OPTS ) = @_;

    my $datastore_path = $self->_datastore_file();
    if ( $OPTS{'lock'} && ( stat($datastore_path) )[4] != $> ) {
        #
        #  If we create a bug where we forgot to change uids
        #  complain loudly (this will not make the behavior safe
        #  it will just warn us if we create a bug)
        #
        _get_locale();
        return ( 0, $locale->maketext( "The system could not load the SSL datastore file “[_1]” because it is inaccessible or owned by the wrong user.", $self->_datastore_file() ) );
    }

    if ( $OPTS{'lock'} && !$INC{'Cpanel/SafeFile.pm'} ) {
        Cpanel::LoadModule::load_perl_module('Cpanel::SafeFile');
    }

    local $Cpanel::SafeFile::LOCK_WAIT_TIME = $SSL_STORAGE_LOCK_WAIT_TIME if $OPTS{'lock'};

    local $Cpanel::CachedDataStore::LAST_WRITE_CACHE_SERIALIZATION_ERROR;

    my $ds = Cpanel::CachedDataStore::loaddatastore(
        $datastore_path,
        $OPTS{'lock'} ? 1 : 0,
        undef,
        { donotlock => !$OPTS{'lock'} }
    );

    $self->_migrate_datastore($ds);

    if ( $ds && ( !$OPTS{'lock'} || $ds->{'fh'} ) ) {
        if ($Cpanel::CachedDataStore::LAST_WRITE_CACHE_SERIALIZATION_ERROR) {
            my $err = $Cpanel::CachedDataStore::LAST_WRITE_CACHE_SERIALIZATION_ERROR;

            $err = "Datastore file “$datastore_path” contains data that cannot be stored as JSON ($err).";
            Cpanel::Debug::log_warn($err);

            $ds->clear_data() if $err;
        }
    }
    else {
        my $err = $!;
        _get_locale();

        if ($err) {
            return ( 0, $locale->maketext( 'The system could not load the SSL datastore file because of an error: [_1]', $err ) );
        }
        return ( 0, $locale->maketext('The system could not load the SSL datastore file because of an unknown error.') );
    }

    return ( 1, $ds );
}

sub precache {
    my ($self) = @_;

    die "Already precached!" if $self->{'_precached_data'};

    my ( $ok, $data ) = $self->_execute_coderef(
        sub {
            return $self->_load_datastore_ro();
        }
    );
    die $data if !$ok;

    $self->{'_precached_data'} = $data;

    return;
}

sub remove_precache {
    my ($self) = @_;

    delete $self->{'_precached_data'} or die "Wasn’t precached!";

    return;
}

sub get_certificate_object {
    my ( $self, $id ) = @_;
    return $self->_execute_coderef(
        sub {
            my $path = $self->get_certificate_path($id);
            return Cpanel::SSL::Objects::Certificate::File->new( path => $path );
        },
    );
}

sub _load_datastore_ro {
    my ( $self, %opts ) = @_;

    #Check for whether we already have a file lock on what we're reading.
    #We have to make a copy in this case to ensure that code that thinks
    #it won't affect anything doesn't inadvertently alter something that
    #will be saved.
    if ( $self->{'_locked_ds'} ) {

        # _find calls us with no_clone since it will already
        # clone the result data.  This avoids cloning ALL
        # the data in the datastore when we are only returning
        # a subset to the caller.
        if ( $opts{'no_clone'} ) {
            return ( 1, $self->{'_locked_ds'}->data() );
        }

        return ( 1, $self->{'_locked_ds'}->data() ) if !ref $self->{'_locked_ds'}->data();
        require Clone;
        return ( 1, Clone::clone( $self->{'_locked_ds'}->data() ) );
    }

    if ( $self->{'_precached_data'} ) {
        return ( 1, $self->{'_precached_data'} );
    }

    my ( $ok, $ds ) = $self->_load_datastore();

    if ( ref $ds && !defined $ds->{'data'} ) {
        return ( 1, {} ) if $self->{'_in_rebuild'};

        if ( !$self->{'_file_did_not_exist'} ) {
            Cpanel::Debug::log_info( 'Rebuilding empty or corrupt SSLStorage datastore: ' . $self->_datastore_file() );
        }

        $self->_rebuild_records();

        ( $ok, $ds ) = $self->_load_datastore();
    }

    return $ok ? ( 1, $ds->{'data'} ) : ( 0, $ds );
}

#NOTE: Writes to the datastore work thus:
#Make changes to the returned hashref from this function.
#Calls to _save_datastore() will grab the object's internal datastore
#hash (which contains a file lock and a filehandle) and do the save.
#
#Each call to _load_datastore_rw increments a "_times_loaded_rw" counter
#which each call to _save_datastore or _unlock_datastore will decrement;
#_save_datastore will only actually *save* when that "_times_loaded_rw"
#counter goes to 0.
#
#This is to facilitate race safety with batch operations: just call
#_load_datastore_rw() before doing anything, then subsequent load/save
#operations will make changes in memory. The code that calls
#_load_datastore_rw() just has to be sure to call either
#_unlock_datastore() or _save_datastore()!
#
# See CPANEL-12180 and CPANEL-12118 for why this hack is necessary
#
sub _load_datastore_rw {
    my ($self) = @_;

    if ( $self->{'_precached_data'} ) {

        # logging for the stacktrace mostly - just to track down other issues this may have caused
        Cpanel::Debug::log_warn("Tried to load the SSL datastore readwrite when data was precached.");
        die 'Not while precached!';
    }

    #No need to make a copy here as in the _ro case above because
    #this caller expects its changes to be saved.
    if ( $self->{'_locked_ds'} ) {
        $self->{'_times_loaded_rw'}++;
        return ( 1, $self->{'_locked_ds'}->data() );
    }

    my ( $ok, $ds ) = $self->_load_datastore( 'lock' => 1 );

    return ( 0, $ds ) if !$ok;

    $self->{'_locked_ds'} = $ds;
    $self->{'_times_loaded_rw'}++;

    if ( !defined $ds->{'data'} ) {
        $ds->{'data'} = {};
        if ( !$self->{'_in_rebuild'} ) {
            if ( !$self->{'_file_did_not_exist'} ) {
                Cpanel::Debug::log_info( 'Rebuilding empty or corrupt SSLStorage datastore: ' . $self->_datastore_file() );
            }
            $self->_rebuild_records();
        }
    }

    return ( 1, $ds->{'data'} );
}

#Call this when aborting a r/w datastore operation.
sub _unlock_datastore {
    my ($self) = @_;

    die "No r/w datastore!\n" if !$self->{'_locked_ds'};    #Implementor error.

    $self->{'_times_loaded_rw'}--;
    return 1 if $self->{'_times_loaded_rw'};

    if ( !Cpanel::CachedDataStore::unlockdatastore( $self->{'_locked_ds'} ) ) {
        my $err = $!;
        _get_locale();
        if ($err) {
            return ( 0, $locale->maketext( 'The system could not unlock the SSL datastore file because of an error: [_1]', $err ) );
        }
        return ( 0, $locale->maketext('The system could not unlock the SSL datastore file because of an unknown error.') );
    }

    delete $self->{'_locked_ds'};
    return 1;
}

sub _save_datastore {
    my ($self) = @_;

    my $datastore_obj = $self->{'_locked_ds'} or die "No r/w datastore!\n";    #Implementor error.

    $self->{'_times_loaded_rw'}--;
    return 1 if $self->{'_times_loaded_rw'};

    my $datastore_file = $self->_datastore_file();

    if ( ( stat($datastore_file) )[4] != $> ) {
        #
        #  If we create a bug where we forgot to change uids
        #  complain loudly (this will not make the behavior safe
        #  it will just warn us if we create a bug)
        #
        require Cpanel::Carp;
        die Cpanel::Carp::safe_longmess("Privilege de-escalation before saving datastore either failed or was omitted.");
    }

    #Added to ensure sanity in the data structures that we save.
    #JSON per se is not important; what is important is that we not
    #accidentally save things we don't mean to save, like scalar references
    #or blessed objects. CPANEL-2008 documents a case of finding the
    #structure from Encoding::BER in the ssl.db files; this should both
    #help to track down that breakage as well as just be a good sanity
    #check hereforward.
    #
    #We use raw JSON::XS here rather than Cpanel::JSON in order to
    #avoid the “safety net” stuff like convert_blessed that
    #Cpanel::JSON enables.
    #
    my $sanity_err;
    try { JSON::XS::encode_json( $datastore_obj->{'data'} ) }
    catch {
        require Cpanel::Carp;
        Cpanel::Debug::log_warn( "Invalid SSLStorage data: $_\n" . Cpanel::Carp::safe_longmess() );
        $sanity_err = $_;
    };

    return ( 0, $sanity_err ) if $sanity_err;

    $datastore_obj->{'mode'} = $DATASTORE_PERMS;

    my ( $err, $ok );
    try {
        $ok = $datastore_obj->save();
    }
    catch {
        $err = $_;
    };

    if ( !$ok || $err ) {
        Cpanel::CachedDataStore::unlockdatastore($datastore_obj);

        warn "$err:$!";
        _get_locale();
        if ($err) {
            return ( 0, $locale->maketext( 'The system could not write the SSL datastore file because of an error: [_1]', $err ) );
        }
        elsif ($!) {
            return ( 0, $locale->maketext( 'The system could not write the SSL datastore file because of an error: [_1]', $! ) );
        }
        return ( 0, $locale->maketext('The system could not write the SSL datastore file because of an unknown error.') );

    }

    delete $self->{'_locked_ds'};
    return 1;
}

#This is for subclassing, so that User instances can protect filesystem access
#using reduced privileges.
sub _execute_coderef {
    my ( $self, $coderef ) = @_;
    return $coderef->();
}

sub _build_import_options {
    my ( $self, $record ) = @_;

    return ( text => $record->{'text'}, id => $record->{'data'}{'id'}, 'created' => $record->{'data'}{'created'} );
}

sub _get_locale {
    return $locale ||= Cpanel::Locale->get_handle();
}

sub DESTROY {
    my ($self) = @_;

    return if $self->{'_pid'} != $$;

    if ( $self->{'_locked_ds'} ) {
        my ( $unlock_status, $unlock_statusmsg ) = $self->_execute_coderef(
            sub {
                $self->_unlock_datastore();
            }
        );

        if ( !$unlock_status ) {
            Cpanel::Debug::log_warn($unlock_statusmsg);
        }

        my $obj_type       = scalar ref $self;
        my $datastore_file = $self->_datastore_file();

        # Do not localize error messages in DESTROY to avoid
        # global destruction loops and allow proper testing

        Cpanel::Debug::log_warn("$obj_type failed to release the lock on datastore file, [$datastore_file] before destruction");
    }
    return 1;
}

1;

__END__

=encoding utf-8

=head1 NAME

Cpanel::SSLStorage - Storage database for SSL resources

=head1 DESCRIPTION

SSLStorage abstracts handling of SSL resources such that external code does not
need to access the filesystem directly. While it currently implements storage
using a filesystem, in theory an SQL backend could work just as well,
notwithstanding the methods below that “leak” the abstraction.

Cpanel::SSLStorage itself is a base class. Instantiate a subclass, not
this class itself.

Most functions in this class return two arguments; they are one of:

    0, "Error message"
    1, $payload

=head1 SYNOPSIS

    #See subclasses for instantiation details.
    my $sslstorage = ...;


    my ( $ok, $found_ar );
    ( $ok, $found_ar ) = $sslstorage->find_keys( modulus => $some_modulus, ... );
    die "$found_ar\n" if !$ok;

    my @key_texts = map {
        my ( $ok, $text ) = $sslstorage->get_key_text($_);
        die "$text\n" if !$ok;
        $text;
    } @$found_ar;

    my $key_path = $sslstorage->get_key_path( $found_ar->[0] );

    my $msg;
    ( $ok, $msg ) = $sslstorage->remove_key( $found_ar->[0] );
    die "$msg\n" if !$ok;

    #Finding, getting, and removing functions exist for "certificate"s as well.

    my $records_ar;
    ( $ok, $records_ar ) = $sslstorage->export();
    die "$export\n" if !$ok;

    ( $ok, $msg ) = $sslstorage->import( $records_ar );
    die "$msg\n" if !$ok;

    ( $ok, $msg ) = $sslstorage->rebuild_records();
    die "$msg\n" if !$ok;

=head1 SUBROUTINES

=head2 precache() remove_precache()

These methods avoid reloading the datastore over and over
when there are many queries to make against the datastore. Only precache when
you know any corruption fixes or other changes to the datastore are done.

If you need to make changes (e.g., to rebuild the datastore), then remove the
precache before you make changes. You can reapply it afterward.

Both of these methods will throw an exception if they’re called
unnecessarily.

=head2 find_keys( <search terms> )  find_certificates( <search terms> )

Look for keys/certificates that match all of the given criteria.
Search terms are passed in as key/value pairs. The return is always
an array reference on success, even if no items match the given criteria.
C<text> may be searched on as well. Two-argument return.

=head2 get_key_text( $key_id_or_record )  get_certificate_text( $cert_id_or_record )

Retrieves the resource’s text from the backend storage. Two-argument return.

=head2 remove_key( id => $key_id ) remove_certificate( id => $cert_id )

Removes the passed-in item (ID or record hash) from the datastore.
Two-argument return.

=head2 export

Return an arrayref of all records in the datastore. This function’s return
can be import()ed to backup and restore a datastore’s contents.
Two-argument return.

=head2 import( $exported_records_ar )

Adds the records from the passed-in arrayref to the datastore.
Two-argument return.

=head2 remove_certificate_and_key( id => $cert_id )

A convenience method that deletes a certificate and whatever key may
match it in a single pass.
Two-argument return.

=head2 add_key_and_certificate_if_needed ( cert => $cert_text, key => $key_text, key_friendly_name => $key_friendly_name, cert_friendly_name => $cert_friendly_name )

A convenience method that adds both a certificate and key if they need to be added to the store. It silently ignores the already added failures.

=head1 ABSTRACTION-LEAKING SUBROUTINES

The following subroutines reveal details of the backend (i.e., filesystem)
storage to callers.

=head2 get_key_path( $key_id_or_record ) get_certificate_path( $cert_id_or_record )

Construct a filesystem path from the passed-in ID or record hash (i.e., a hash
such as those returned from find_*). Since this method cannot fail, it returns
a single scalar. DO NOT CALL THESE METHODS UNLESS YOU ABSOLUTELY NEED THE
FILESYSTEM PATH--e.g., constructing Apache’s configuration file.

=head2 rebuild_records

Rebuild the datastore file(s) based on the filesystem contents, salvaging what
information may be gleaned from the existing datastore. This method is called
automatically if datastore corruption is detected. Two-argument return.

=cut
