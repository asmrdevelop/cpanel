package Cpanel::UniqId;

use XSLoader ();
use Exporter ();

our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(getuniqid);
our $VERSION   = '0.2';

XSLoader::load 'Cpanel::UniqId', $Cpanel::UniqId::VERSION;

1;

__END__
