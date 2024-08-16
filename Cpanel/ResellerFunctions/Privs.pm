package Cpanel::ResellerFunctions::Privs;

use Cpanel::Reseller ();

sub hasresellerpriv {
    goto &Cpanel::Reseller::hasresellerpriv;
}

1;
