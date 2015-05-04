###
    Copyright 2015, Quixey Inc.
    All rights reserved.

    Licensed under the Modified BSD License found in the
    LICENSE file in the root directory of this source tree.
###


J.dc 'Expandable',
    props:
        heading:
            type: $$.element
        contractedChildren:
            type: $$.bool
            default: true
        initialExpanded:
            default: false
        iconSize:
            default: 14
        style:
            type: $$.style
            default: {}

    state:
        expanded:
            default: -> @prop.initialExpanded()


    render: ->
        $$ ('div'),
            style: @prop.style().toObj()
            onClick:
                if not @expanded()
                    (e) => @expanded true

            $$ ('TableRow'),
                style:
                    width: '100%'

                $$ ('td'),
                    style:
                        verticalAlign: 'top'
                        width: 18
                        paddingRight: 4
                        cursor: 'pointer'
                    onClick:
                        if @expanded()
                            (e) => @expanded false

                    $$ ('img'),
                        src: "/images/#{if @expanded() then 'expanded.png' else 'contracted.png'}"
                        style:
                            maxHeight: @prop.iconSize()
                            maxWidth: @prop.iconSize()

                $$ ('td'),
                    style:
                        verticalAlign: 'top'

                    if @prop.heading()?
                        $$ ('div'),
                            style:
                                cursor: 'pointer'
                            onClick:
                                if @expanded()
                                    (e) => @expanded false

                            (@prop.heading())

                            if not @expanded()
                                (@prop.contractedChildren())

                    if @expanded()
                        (@prop.children())