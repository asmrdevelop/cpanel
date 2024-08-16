package Cpanel::POSIX::Tiny;

our $VERSION = '1.3';

use AutoLoader;
use XSLoader ();
require Exporter;

our @ISA       = qw(Exporter);
our @EXPORT    = ();
our @EXPORT_OK = qw(uname nice setsid pipe close times sysconf write closefds daemonclosefds dup2);

our $AUTOLOAD;

XSLoader::load 'Cpanel::POSIX::Tiny', $VERSION;

my $EINVAL = constant( "EINVAL", 0 );
my $EAGAIN = constant( "EAGAIN", 0 );

sub AUTOLOAD {
    if ( $AUTOLOAD =~ /::(_?[a-z])/ ) {

        # require AutoLoader;
        $AutoLoader::AUTOLOAD = $AUTOLOAD;
        goto &AutoLoader::AUTOLOAD;
    }
    local $! = 0;
    my $constname = $AUTOLOAD;
    $constname =~ s/.*:://;
    my $val = constant( $constname, @_ ? $_[0] : 0 );
    if ( $! == 0 ) {
        *$AUTOLOAD = sub { $val };
    }
    elsif ( $! == $EAGAIN ) {    # Not really a constant, so always call.
        *$AUTOLOAD = sub { constant( $constname, $_[0] ) };
    }
    elsif ( $! == $EINVAL ) {
        die "$constname is not a valid POSIX macro";
    }
    else {
        die "Your vendor has not defined POSIX macro $constname, used";
    }

    goto &$AUTOLOAD;
}

1;

__END__
