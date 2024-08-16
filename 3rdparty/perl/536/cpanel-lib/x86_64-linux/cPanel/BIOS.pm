package cPanel::BIOS;

use XSLoader ();

our $VERSION   = '0.10';

XSLoader::load 'cPanel::BIOS', $cPanel::BIOS::VERSION;

1;

__END__
