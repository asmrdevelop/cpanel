# NOTE: Derived from blib/lib/Data/Validate.pm.
# Changes made here will be lost when autosplit is run again.
# See AutoSplit.pm.
package Data::Validate;

#line 720 "blib/lib/Data/Validate.pm (autosplit into blib/lib/auto/Data/Validate/is_odd.al)"
# -------------------------------------------------------------------------------


sub is_odd{
	my $self = shift if ref($_[0]);
	my $value = shift;
	
	return unless defined(is_numeric($value));
	my $untainted = is_integer($value);
	return unless defined($untainted);
	
	return $untainted if $value % 2;
	
	return;
}

# end of Data::Validate::is_odd
1;
