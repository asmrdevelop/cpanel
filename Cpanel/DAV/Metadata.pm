package Cpanel::DAV::Metadata;

# cpanel - Cpanel/DAV/Metadata.pm                  Copyright 2024 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
use cPstrict;

use Cpanel::DAV::Logger qw{logfunc dbg};
use Cpanel::Rand::Get   ();

my %meta_cache_by_file;

my @base_meta_props     = qw{displayname type description protected};
my @cal_only_meta_props = qw{calendar-order calendar-color calendar-timezone default-calendar-privilege-set};
our @metadata_props = ( @cal_only_meta_props, @base_meta_props );

=head1 NAME

Cpanel::DAV::Metadata - The metadata (name, description, color, etc.) for each calendar and address book

=head1 METHODS

=head2 new(%args)

Constructor. Required opts are C<homedir> (sys user homedir) and C<user> (DAV user).

=cut

sub new ( $class, %args ) {
    logfunc(1);

    die 'Need home directory and user passed in' if !$args{"homedir"} || !$args{"user"};
    my $self = bless {%args}, $class;
    $self->{'dav_root'} = $self->{'homedir'} . '/.caldav/' . $self->{'user'};

    $self->{'valid_keys_by_file'} = {
        $self->{'dav_root'} . '/.metadata' => \@metadata_props,
    };

    return $self;
}

=head2 load($path, $force)

Given a full path ($path) to the desired .metadata file on disk, load and parse the contents.
Returns a hash ref structured by collection and key. If $force is set, the in-memory cache
will not be used even if present.

=cut

sub load ( $self, $path = '', $force = 0 ) {
    logfunc(1);

    # If not overriden, use the default
    $path ||= $self->{'dav_root'} . '/.metadata';
    dbg("=[load]= : path: $path ");

    # Return a copy
    return { %{ $meta_cache_by_file{$path} } } if !$force && ref $meta_cache_by_file{$path} eq 'HASH';

    my %data;

    # Perhaps should warn if open fails?
    open( my $fh, '<', $path ) or return \%data;

    # dbg("=[load]= opened file for reading" );
    my ( $collection, $key );
    while ( my $l = <$fh> ) {
        chomp($l);

        # Note, comments only valid if starting line.
        next if !length $l || index( $l, '#' ) == 0;

        # dbg( "=[load]= l=$l");
        # Find collection headers, this is for the path
        if ( $l =~ m/^\[(.*)\]$/ ) {
            $collection = $1;

            # dbg("=[load]= setting collection = $collection");
            next;
        }

        # Move on if clearly bogus till next collection sighted
        next if defined $collection && !length $collection;

        # Look for continuation lines of properties, like calendar-timezone,
        # that can span 10+ lines. Currently just using "^^^ " prepended to the lines
        if ( index( $l, "^^^^ " ) == 0 && defined $key ) {
            my $data = substr( $l, 5 );

            # We need to ensure there's a newline at the end of the existing value before appending new data
            if ( $data{$collection}{$key} !~ m/\n$/ ) {
                $data{$collection}{$key} .= "\n";
            }
            $data{$collection}{$key} .= $data . "\n";
            next;
        }
        ( $key, my $val ) = split( /\s+/, $l, 2 );

        # Strip out garbage if we know what's valid for the file
        if ( ref $self->{'valid_keys_by_file'}{$path} eq 'ARRAY' ) {
            next if !grep { $_ eq $key } @{ $self->{'valid_keys_by_file'}{$path} };
        }
        $data{$collection}{$key} = $val;
    }
    close($fh);    # technically will close with return, so could cull this line

    dbg( "=[load]= : returning:", \%data );
    $meta_cache_by_file{$path} = {%data};    # Cache a copy to protect internal ref
    return \%data;
}

=head2 save($metadata_hr, $path)

Save the specified metadata ($metadata_hr) to the .metadata path specified in
$path (or if not specified, then to the file located within the current instance's
DAV root).

NOTE: This does not check whether you *should* be able to save this.
If you are a webmail user running as cpuser context, be sure to check
before write with something like Cpanel::DAV::CaldavCarddav::modify_metadata
instead of using this.
You will, of course, fail past user boundary, as permissions stop that.

=cut

sub save ( $self, $metadata_hr, $path = '' ) {
    logfunc(1);
    $path ||= $self->{'dav_root'} . '/.metadata';

    require Cpanel::Rand::Get;
    my $tmp_path = $path . '.' . Cpanel::Rand::Get::getranddata(8);
    dbg("=[save]= path is $path");

    my $out = '';
    foreach my $collection ( keys %{$metadata_hr} ) {
        $out .= "[$collection]\n";
        foreach my $propname ( keys %{ $metadata_hr->{$collection} } ) {
            my $first = 1;
            next if !$metadata_hr->{$collection}{$propname};
            foreach my $line ( split( /\r?\n/, $metadata_hr->{$collection}{$propname} ) ) {
                next if !length $line;
                if ($first) {
                    $out .= "$propname $line\n";
                    $first = 0;
                    next;
                }
                $out .= "^^^^ $line\n";
            }
        }
    }

    open( my $fh, '>', $tmp_path ) or die "Couldn't open $tmp_path for writing: $!";
    print $fh $out;
    close($fh);

    _rename( $tmp_path, $path ) or die "Couldn't rename $tmp_path to $path: $!";
    $meta_cache_by_file{$path} = {%$metadata_hr};
    return 1;
}

# for mocking in tests.
sub _rename ( $src, $dest ) { return rename( $src, $dest ) }

1;
