package IO::CloseFDs;

use XSLoader ();
use Exporter ();

our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(closefds);
our $VERSION   = '1.01';

XSLoader::load( 'IO::CloseFDs', $IO::CloseFDs::VERSION );

1;

__END__
