package Cpanel::Cleanup;

use XSLoader ();
use Exporter ();

our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(closefds);
our $VERSION   = '0.4';

XSLoader::load 'Cpanel::Cleanup', $Cpanel::Cleanup::VERSION;

1;

__END__
