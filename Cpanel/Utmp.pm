package Cpanel::Utmp;

# cpanel - Cpanel/Utmp.pm                          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::Exception        ();
use Cpanel::Fcntl::Constants ();

#Made a global for testing.
our $UTMP_FILE = '/var/run/utmp';

#FYI:
#https://dl.dropboxusercontent.com/u/4219104/codes/utmp_parser.py
#Python: h i 32s 4s 32s 256s h h i i i 36x

#Type annotations are from the utmp(5) man page:
my @PACK_TEMPLATE_PARTS = (

    #type of login
    #short
    [ ut_type => 'S' ],

    #PID of login process
    #pid_t
    [ ut_pid => 'x2 L' ],    #Pad 2 bytes from the previous value.

    #device name of tty - "/dev/"
    #char[UT_LINESIZE = 32]
    [ ut_line => 'Z32' ],

    #init id or abbrev. ttyname
    #char[4]
    [ ut_id => 'Z4' ],

    #user name
    #char[UT_NAMESIZE = 32]
    [ ut_user => 'Z32' ],

    #hostname for remote login
    #char[UT_HOSTSIZE = 256]
    [ ut_host => 'Z256' ],

    #The exit status of a process marked as DEAD_PROCESS:
    (

        #process termination status
        #short int
        [ e_termination => 'S' ],

        #process exit status
        #short int
        [ e_exit => 'S' ],
    ),

    #Session ID, used for windowing
    #64-bit: int32_t
    #others: long
    [ ut_session => 'L' ],

    #Time entry was made
    (

        #Seconds
        #64-bit: int32_t
        #others: timeval.tv_sec
        [ tv_sec => 'L' ],

        #Microseconds
        #64-bit: int32_t
        #others: timeval.tv_usec
        [ tv_usec => 'L' ],
    ),

    #IP address of remote host
    #int32_t[4]
    [ ut_addr_v6 => 'a16' ],

    #Reserved for future use
    #char[20]
    [ __unused => 'x20' ],
);

my ( $PACK_TEMPLATE, @PACK_TEMPLATE_ORDER, $PACK_TEMPLATE_SIZE, @STRING_LABELS );

sub new {
    my ($class) = @_;

    local $!;
    open my $rfh, '<', $UTMP_FILE or do {
        die Cpanel::Exception::create( 'IO::FileOpenError', [ path => $UTMP_FILE, error => $!, mode => '<' ] );
    };

    my $self = {
        _chunk => q<>,
        _rfh   => $rfh,
    };

    if ( !$PACK_TEMPLATE ) {
        $PACK_TEMPLATE      = join( q< >, map { $_->[1] } @PACK_TEMPLATE_PARTS );
        $PACK_TEMPLATE_SIZE = length pack( $PACK_TEMPLATE, () );

        #NOTE: These keys are underscore-prefixed for insertion into
        #Cpanel::Utmp::Entry::new().
        @PACK_TEMPLATE_ORDER = map { '_' . $_->[0] } @PACK_TEMPLATE_PARTS;

        @STRING_LABELS = map { $_->[0] } grep { $_->[1] =~ tr<Z><> } @PACK_TEMPLATE_PARTS;
    }

    bless $self, $class;

    $self->_seek_to_end();

    return $self;
}

#This finds the most recent item before what the previous
#query returned that matches the given query.
#
#e.g. tv_sec => qr<\A 1409202733 \z>x
#
#If all you want is the next most recent entry,
#do a "dummy" search like: ut_type => qr<.>
#
sub find_most_recent {
    my ( $self, $key, $regexp ) = @_;

    #If we're searching on a string, then we don't have to create a new
    #hash for each entry.
    my $this_is_a_string_search = grep { $_ eq $key } @STRING_LABELS;

    my $key_is_a_method = Cpanel::Utmp::Entry->can($key);

    while (1) {
        $self->_read_previous_chunk() or return undef;

        my $record = $self->_make_record_from_chunk();

        if ( ( $key_is_a_method ? $record->$key() : $record->get($key) ) =~ $regexp ) {
            return $record;
        }
    }

    return undef;
}

sub _make_record_from_chunk {
    my ($self) = @_;

    my %record;
    my @unpacked = unpack( $PACK_TEMPLATE, $self->{'_chunk'} );
    @record{@PACK_TEMPLATE_ORDER} = @unpacked;

    delete $record{'___unused'};

    return Cpanel::Utmp::Entry->new( \%record );
}

sub _seek_back {
    my ($self) = @_;

    return undef if !tell $self->{'_rfh'};

    local $!;
    return seek( $self->{'_rfh'}, 0 - $PACK_TEMPLATE_SIZE, $Cpanel::Fcntl::Constants::SEEK_CUR ) || do {
        die Cpanel::Exception::create(
            'IO::FileSeekError',
            [
                error    => $!,
                path     => $UTMP_FILE,
                position => 0 - $PACK_TEMPLATE_SIZE,
                whence   => $Cpanel::Fcntl::Constants::SEEK_CUR,
            ]
        );
    };
}

sub _seek_to_end {
    my ($self) = @_;

    local $!;
    return seek( $self->{'_rfh'}, 0, $Cpanel::Fcntl::Constants::SEEK_END ) || do {
        die Cpanel::Exception::create(
            'IO::FileSeekError',
            [
                error    => $!,
                path     => $UTMP_FILE,
                position => 0,
                whence   => $Cpanel::Fcntl::Constants::SEEK_END,
            ]
        );
    };
}

#Retreats by one.
sub _read_previous_chunk {
    my ($self) = @_;

    $self->_seek_back() or return undef;

    $self->_read_chunk();

    return $self->_seek_back();
}

#Advances by one.
sub _read_chunk {
    my ($self) = @_;

    local $!;
    my $read = CORE::read( $self->{'_rfh'}, $self->{'_chunk'}, $PACK_TEMPLATE_SIZE );
    if ($!) {
        die Cpanel::Exception::create( 'IO::ReadError', [ error => $! ] );
    }

    return $read;
}

#----------------------------------------------------------------------

package Cpanel::Utmp::Entry;

use strict;

#This receives a hash with keys like '_ut_addr_v6' (i.e., leading underscore).
#It's a bit less than ideal, but since this class is so predisposed to working
#with Cpanel::Utmp, it seems not so bad. And definitely simpler.
sub new {
    my ( $class, $self ) = @_;

    return bless $self, $class;
}

#This returns in IPv4 format if the last 96 bits are null;
#otherwise, it returns an expanded-format IPv6 address.
sub ip_address {
    my ($self) = @_;

    my $binary = $self->get('ut_addr_v6');

    #If everything after the last octet is NULL, then we
    #consider this to be an IPv4 address.
    if ( substr( $binary, 4 ) !~ tr<\0><>c ) {
        return join( '.', unpack 'C4', substr( $binary, 0, 4 ) );
    }

    #It's IPv6, hm? Ok.
    #Split it into pairs of bytes, convert to hex, then join.
    return join ':', map { unpack 'H4', $_ } ( $binary =~ m<..>gs );
}

sub get {
    my ( $self, $what ) = @_;

    return $self->{"_$what"};
}

1;
