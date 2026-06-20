function [z_final] = reduce_fjd(z_initial)
z = z_initial;
while z> 75
    z = z-1;
end
z_final = z;

end