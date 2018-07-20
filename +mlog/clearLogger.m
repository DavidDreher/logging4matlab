function clearLogger(name)
    [~, destructor] = mlog.getLogger(name);
    destructor();
end

