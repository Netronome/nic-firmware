find ./ -iname '*.h' -exec sed -i 's/[[:space:]]\+$//' {} \;
find ./ -iname '*.c' -exec sed -i 's/[[:space:]]\+$//' {} \;
find ./ -iname '*.uc' -exec sed -i 's/[[:space:]]\+$//' {} \;

