package Cpanel::DataStore;

# cpanel - Cpanel/DataStore.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;
use Cpanel::Debug ();

sub store_ref {
    my ( $file, $outof_ref, $perm ) = @_;

    # We don't want this linked to all binaries using this so we require() it
    # We do it here so we don't even have to load it if it isn't used.
    # That savings is probably worth the extra exists() that calling require() multiple times would do
    require Cpanel::YAML::Syck;

    # make Load recognize various implicit types in YAML, such as unquoted true, false,
    # as well as integers and floating-point numbers. Otherwise, only ~ is recognized
    # to be undef.
    $YAML::Syck::ImplicitTyping = 0;

    # These will keep updates from making a bunch of unrelated changes when
    # updating existing files.
    #
    # We write it this way because it avoids us needing to use "no warnings
    # 'once'" over a large block scope, as turning off individual warnings for a
    # large block increases memory usage.
    local $YAML::Syck::SingleQuote;
    local $YAML::Syck::SortKeys;

    $YAML::Syck::SingleQuote = 1;
    $YAML::Syck::SortKeys    = 1;

    # Currently we assume caller already did due diligence in sending a valid handle.
    # If we don't mind the overhead we could assure it is an open handle:
    #    if (ref($file) || ref(\$file) eq 'GLOB' || (defined &Scalar::Util::openhandle && Scalar::Util::openhandle($file)) ) {
    if ( ref($file) ) {

        my $yaml_string = YAML::Syck::Dump($outof_ref);

        # Assume caller already did due diligence in sending a ready-to-write-to FH
        print( {$file} _format($yaml_string) ) || return;
        return $file;
    }

    if ( ref($perm) eq 'ARRAY' && !-l $file && !-e $file ) {
        require Cpanel::FileUtils::TouchFile;    # or use() ?

        my $touch_chmod = sub {
            if ( !Cpanel::FileUtils::TouchFile::touchfile($file) ) {
                Cpanel::Debug::log_info("Could not touch \xE2\x80\x9C$file\xE2\x80\x9D: $!");
                return;
            }

            if ( $perm->[0] ) {
                if ( !chmod( oct( $perm->[0] ), $file ) ) {
                    Cpanel::Debug::log_info("Could not chmod \xE2\x80\x9C$file\xE2\x80\x9D to \xE2\x80\x9C$perm->[0]\xE2\x80\x9D: $!");
                    return;
                }
            }

            return 1;
        };

        if ( $> == 0 && $perm->[1] && $perm->[1] ne 'root' ) {
            require Cpanel::AccessIds::ReducedPrivileges;    # or use() ?
            Cpanel::AccessIds::ReducedPrivileges::call_as_user( $perm->[1], $touch_chmod ) || return;
        }
        else {
            $touch_chmod->() || return;
        }
    }

    if ( open my $yaml_out, '>', $file ) {
        my $yaml_string = YAML::Syck::Dump($outof_ref);
        print {$yaml_out} _format($yaml_string);
        close $yaml_out;
        return 1;
    }
    else {
        Cpanel::Debug::log_warn("Could not open file '$file' for writing: $!");
        return;
    }
}

#
# *** Do not use fetch_ref in new code.
# It will silently discard data that is not
# in the format requested and return an empty
#
sub fetch_ref {
    my ( $file, $is_array ) = @_;

    my $fetch_ref = load_ref($file);

    my $data_type = ref $fetch_ref;
    my $data      = $data_type ? $fetch_ref : undef;
    $data_type ||= 'UNDEF';

    if ( $is_array && $data_type ne 'ARRAY' ) {
        return [];
    }
    elsif ( !$is_array && $data_type ne 'HASH' ) {
        return {};
    }

    return $data;
}

#NOTE: This overwrites both $! and $@.
sub load_ref {
    my ( $file, $into_ref ) = @_;
    return if ( !-e $file || -z _ );

    # We don't want this linked to all binaries using this so we require() it
    # We do it here so we don't even have to load it if it isn't used.
    # That savings is probably worth the extra exists() that calling require() multiple times would do
    require Cpanel::YAML::Syck;

    # make Load recognize various implicit types in YAML, such as unquoted true, false,
    # as well as integers and floating-point numbers. Otherwise, only ~ is recognized
    # to be undef.
    $YAML::Syck::ImplicitTyping = 0;

    my $struct;

    # Currently we assume caller already did due diligence in sending a valid handle.
    # If we don't mind the overhead we could assure it is an open handle:
    #    if (ref($file) || ref(\$file) eq 'GLOB' || (defined &Scalar::Util::openhandle && Scalar::Util::openhandle($file)) ) {
    if ( ref($file) ) {

        # Assume caller already did due diligence in sending a ready-to-read-from FH
        local $!;
        $struct = eval {
            local $/;
            local $SIG{__WARN__};
            local $SIG{__DIE__};
            ( YAML::Syck::Load(<$file>) )[0];
        };
        Cpanel::Debug::log_warn("Error loading YAML data: $!") if ( !$struct );
    }
    elsif ( open my $yaml_in, '<', $file ) {
        local $!;
        $struct = eval {
            local $/;
            local $SIG{__WARN__};
            local $SIG{__DIE__};
            ( YAML::Syck::Load(<$yaml_in>) )[0];
        };
        Cpanel::Debug::log_warn("Error loading YAML data: $!") if ( !$struct );
        close $yaml_in;
    }
    else {
        my $err = $!;
        Cpanel::Debug::log_warn("Could not open file '$file' for reading: $err");
        return;
    }

    if ( !$struct ) {
        Cpanel::Debug::log_warn("Failed to load YAML data from file $file");
        return;
    }

    if ( defined $into_ref ) {
        my $type      = ref $into_ref;
        my $yaml_type = ref $struct;
        if ( $yaml_type ne $type ) {
            Cpanel::Debug::log_warn("Invalid data type from file $file! YAML type $yaml_type does not match expected type $type. Data ignored!");
            return;    # if we want an empty ref on failure use fetch_ref()
        }

        if ( $yaml_type eq 'HASH' ) {
            %{$into_ref} = %{$struct};
        }
        elsif ( $yaml_type eq 'ARRAY' ) {
            @{$into_ref} = @{$struct};
        }
        else {
            Cpanel::Debug::log_warn("YAML in '$file' is not a hash or array reference");
            return;    # if we want an empty ref on failure use fetch_ref()
        }

        return $into_ref;
    }

    return $struct;
}

sub edit_datastore {
    my ( $file, $editor_cr, $is_array ) = @_;

    if ( ref $editor_cr ne 'CODE' ) {
        Cpanel::Debug::log_warn('second arg needs to be a coderef');
        return;
    }

    my $ref = $is_array ? [] : {};

    if ( !-e $file ) {
        Cpanel::Debug::log_info("Data store file $file does not exist. Attempting to create empty datastore.");
        store_ref( $file, $ref );
    }

    if ( load_ref( $file, $ref ) ) {
        if ( $editor_cr->($ref) ) {
            if ( !store_ref( $file, $ref ) ) {
                Cpanel::Debug::log_warn("Modifications to file $file could not be saved");
                return;
            }
        }
    }
    else {
        Cpanel::Debug::log_warn("Could not load datastore $file");
        return;
    }

    return 1;
}

sub _format {
    my ($s) = @_;

    $s =~ s/[ \t]+$//mg;
    return __grapheme_to_character($s);
}

# We have a CPAN module for this that we may want to incorporate parts
# of into Cpanel modules, but until that is online we do the basic here
sub __grapheme_to_character {
    my ($yaml_string) = @_;

    $yaml_string = quotemeta($yaml_string);
    $yaml_string =~ s/\\{2}x/\\x/g;
    $yaml_string = eval qq{"$yaml_string"};

    return $yaml_string;
}

1;

__END__

=head1 SYNOPSIS

Stores one ref into a file and fetches that ref out of a file:

=over 4

=item * without needing to figure out the array ref slice from the YAML::Tiny fetcher

=item * more intuitive (hopefully) use and names

=item * boolean return

=item * problem logging

=back

    # $file can be a path or a handle (ready to be written to or read from in the appropriate context)
    if( Cpanel::DataStore::store_ref( $file, $ref ) ) {
        print "Successfully stored ref into file!";
    }
    else {
        print "Failed to store ref in file!";
    }

    if( Cpanel::DataStore::load_ref( $file, $ref ) ) {
        print "Successfully put file in ref!";
    }
    else {
        print "Failed to put file into ref!";
    }

# always returns a hashref, even empty on failure (or success...)
    my $hashref  = Cpanel::DataStore::fetch_ref( $file );

# to do the same but with an array ref pass a second true arg:
    my $arrayref = Cpanel::DataStore::fetch_ref( $file, 1 );

=head1 quick, consistent, simple editing:

if ( ___needs_to_update_datastore ) {
    # $file must be a path, handles not supported here
    Cpanel::DataStore::edit_datastore(
        $file,
        sub {
            my ($hr) = @_;
            # change $hr
            return; # return 1; to save changes, return; to not save them
        }
    );
}

=head1 Storing to non-existent files

A 3rd argument to store_ref() can define what to do if the file (a path not a handle) we are storing into does not exist.

It must be an array reference.

=over 4

=item * []

touch the file

=item * ["600"]

chmod the file to the given mode after touching it.

=item * [0,"dantest"]

If you are root, do the touch as the given user. No chmod.

=item * ["0640","dantest"]

If you are root, do the touch and chmod to the given mode as the given user.

=back

=head1 Misc

# TODO (maybe ??): allow the "$file" arg above to be a code ref that "store"s and "fetch"es the ref via a database or whatever
