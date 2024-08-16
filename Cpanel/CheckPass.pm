package Cpanel::CheckPass;

# cpanel - Cpanel/CheckPass.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use Cpanel::CheckPass::AP   ();
use Cpanel::CheckPass::UNIX ();
use Crypt::Passwd::XS       ();

our $VERSION = '1.1';

# these four aliases are currently unused in our codebase
*unix_md5_crypt   = *Crypt::Passwd::XS::unix_md5_crypt;
*to64             = *Cpanel::CheckPass::AP::to64;
*getsalt          = *Cpanel::CheckPass::UNIX::getsalt;
*apache_md5_crypt = *Cpanel::CheckPass::AP::apache_md5_crypt;

sub checkpassword {
    my ( $password, $cryptedpassword ) = @_;
    if ( $cryptedpassword =~ /^\$apr1\$/ ) {
        return Cpanel::CheckPass::AP::checkpassword( $password, $cryptedpassword );
    }
    else {
        return Cpanel::CheckPass::UNIX::checkpassword( $password, $cryptedpassword );
    }
}

1;
