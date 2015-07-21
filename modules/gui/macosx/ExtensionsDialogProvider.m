/*****************************************************************************
 * ExtensionsDialogProvider.m: Mac OS X Extensions Dialogs
 *****************************************************************************
 * Copyright (C) 2010-2013 VLC authors and VideoLAN
 * $Id$
 *
 * Authors: Pierre d'Herbemont <pdherbemont # videolan org>
 *          Brendon Justin <brendonjustin@gmail.com>,
 *          Derk-Jan Hartman <hartman@videolan dot org>,
 *          Felix Paul Kühne <fkuehne@videolan dot org>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/

#import "ExtensionsDialogProvider.h"

#import "intf.h"
#import "ExtensionsManager.h"
#import "misc.h"
#import "VLCUIWidgets.h"

#import <WebKit/WebKit.h>
#import <stdlib.h>

/*****************************************************************************
 * VLCExtensionsDialogProvider implementation
 *****************************************************************************/

static int extensionDialogCallback(vlc_object_t *p_this, const char *psz_variable,
                                   vlc_value_t old_val, vlc_value_t new_val,
                                   void *param);

static NSView *createControlFromWidget(extension_widget_t *widget, id self)
{
    @autoreleasepool {
        assert(!widget->p_sys_intf);
        switch (widget->type) {
            case EXTENSION_WIDGET_HTML:
            {
                WebView *webView = [[WebView alloc] initWithFrame:NSMakeRect (0,0,1,1)];
                [webView setAutoresizingMask:NSViewHeightSizable | NSViewWidthSizable];
                [webView setDrawsBackground:NO];
                return webView;
            }
            case EXTENSION_WIDGET_LABEL:
            {
                NSTextField *field = [[NSTextField alloc] init];
                [field setEditable:NO];
                [field setBordered:NO];
                [field setDrawsBackground:NO];
                [field setFont:[NSFont systemFontOfSize:0]];
                [[field cell] setControlSize:NSRegularControlSize];
                [field setAutoresizingMask:NSViewNotSizable];
                return field;
            }
            case EXTENSION_WIDGET_TEXT_FIELD:
            {
                VLCDialogTextField *field = [[VLCDialogTextField alloc] init];
                [field setWidget:widget];
                [field setAutoresizingMask:NSViewWidthSizable];
                [field setFont:[NSFont systemFontOfSize:0]];
                [[field cell] setControlSize:NSRegularControlSize];
                [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(syncTextField:)  name:NSControlTextDidChangeNotification object:field];
                return field;
            }
            case EXTENSION_WIDGET_CHECK_BOX:
            {
                VLCDialogButton *button = [[VLCDialogButton alloc] init];
                [button setButtonType:NSSwitchButton];
                [button setWidget:widget];
                [button setAction:@selector(triggerClick:)];
                [button setTarget:self];
                [[button cell] setControlSize:NSRegularControlSize];
                [button setAutoresizingMask:NSViewWidthSizable];
                return button;
            }
            case EXTENSION_WIDGET_BUTTON:
            {
                VLCDialogButton *button = [[VLCDialogButton alloc] init];
                [button setBezelStyle:NSRoundedBezelStyle];
                [button setWidget:widget];
                [button setAction:@selector(triggerClick:)];
                [button setTarget:self];
                [[button cell] setControlSize:NSRegularControlSize];
                [button setAutoresizingMask:NSViewNotSizable];
                return button;
            }
            case EXTENSION_WIDGET_DROPDOWN:
            {
                VLCDialogPopUpButton *popup = [[VLCDialogPopUpButton alloc] init];
                [popup setAction:@selector(popUpSelectionChanged:)];
                [popup setTarget:self];
                [popup setWidget:widget];
                return popup;
            }
            case EXTENSION_WIDGET_LIST:
            {
                NSScrollView *scrollView = [[NSScrollView alloc] init];
                [scrollView setHasVerticalScroller:YES];
                VLCDialogList *list = [[VLCDialogList alloc] init];
                [list setUsesAlternatingRowBackgroundColors:YES];
                [list setHeaderView:nil];
                [list setAllowsMultipleSelection:YES];
                [scrollView setDocumentView:list];
                [scrollView setAutoresizingMask:NSViewHeightSizable | NSViewWidthSizable];

                NSTableColumn *column = [[NSTableColumn alloc] init];
                [list addTableColumn:column];
                [list setDataSource:list];
                [list setDelegate:self];
                [list setWidget:widget];
                return scrollView;
            }
            case EXTENSION_WIDGET_IMAGE:
            {
                NSImageView *imageView = [[NSImageView alloc] init];
                [imageView setAutoresizingMask:NSViewHeightSizable | NSViewWidthSizable];
                [imageView setImageFrameStyle:NSImageFramePhoto];
                [imageView setImageScaling:NSImageScaleProportionallyUpOrDown];
                return imageView;
            }
            case EXTENSION_WIDGET_SPIN_ICON:
            {
                NSProgressIndicator *spinner = [[NSProgressIndicator alloc] init];
                [spinner setUsesThreadedAnimation:YES];
                [spinner setStyle:NSProgressIndicatorSpinningStyle];
                [spinner setDisplayedWhenStopped:YES];
                [spinner startAnimation:self];
                return spinner;
            }
            default:
                return nil;
        }
    }
}

static void updateControlFromWidget(NSView *control, extension_widget_t *widget, id self)
{
    @autoreleasepool {
        switch (widget->type) {
            case EXTENSION_WIDGET_HTML:
            {
                // Get the web view
                assert([control isKindOfClass:[WebView class]]);
                WebView *webView = (WebView *)control;
                NSString *string = toNSStr(widget->psz_text);
                [[webView mainFrame] loadHTMLString:string baseURL:[NSURL URLWithString:@""]];
                [webView setNeedsDisplay:YES];
                break;
            }
            case EXTENSION_WIDGET_LABEL:
            case EXTENSION_WIDGET_PASSWORD:
            case EXTENSION_WIDGET_TEXT_FIELD:
            {
                if (!widget->psz_text)
                    break;
                assert([control isKindOfClass:[NSControl class]]);
                NSControl *field = (NSControl *)control;
                NSString *string = toNSStr(widget->psz_text);
                NSAttributedString *attrString = [[NSAttributedString alloc] initWithHTML:[string dataUsingEncoding: NSISOLatin1StringEncoding] documentAttributes:NULL];
                [field setAttributedStringValue:attrString];
                break;
            }
            case EXTENSION_WIDGET_CHECK_BOX:
            case EXTENSION_WIDGET_BUTTON:
            {
                assert([control isKindOfClass:[NSButton class]]);
                NSButton *button = (NSButton *)control;
                [button setTitle:toNSStr(widget->psz_text)];
                if (widget->type == EXTENSION_WIDGET_CHECK_BOX)
                    [button setState:widget->b_checked ? NSOnState : NSOffState];
                break;
            }
            case EXTENSION_WIDGET_DROPDOWN:
            {
                assert([control isKindOfClass:[NSPopUpButton class]]);
                NSPopUpButton *popup = (NSPopUpButton *)control;
                [popup removeAllItems];
                struct extension_widget_value_t *value;
                for (value = widget->p_values; value != NULL; value = value->p_next)
                    [[popup menu] addItemWithTitle:toNSStr(value->psz_text) action:nil keyEquivalent:@""];

                [popup synchronizeTitleAndSelectedItem];
                [self popUpSelectionChanged:popup];
                break;
            }
            case EXTENSION_WIDGET_LIST:
            {
                assert([control isKindOfClass:[NSScrollView class]]);
                NSScrollView *scrollView = (NSScrollView *)control;
                assert([[scrollView documentView] isKindOfClass:[VLCDialogList class]]);
                VLCDialogList *list = (VLCDialogList *)[scrollView documentView];

                NSMutableArray *contentArray = [NSMutableArray array];
                struct extension_widget_value_t *value;
                for (value = widget->p_values; value != NULL; value = value->p_next)
                {
                    NSDictionary *entry = [NSDictionary dictionaryWithObjectsAndKeys:
                                           [NSNumber numberWithInt:value->i_id], @"id",
                                           [NSString stringWithUTF8String:value->psz_text], @"text",
                                           nil];
                    [contentArray addObject:entry];
                }
                list.contentArray = contentArray;
                [list reloadData];
                break;
            }
            case EXTENSION_WIDGET_IMAGE:
            {
                assert([control isKindOfClass:[NSImageView class]]);
                NSImageView *imageView = (NSImageView *)control;
                NSString *string = widget->psz_text ? [NSString stringWithUTF8String:widget->psz_text] : nil;
                NSImage *image = nil;
                if (string)
                    image = [[NSImage alloc] initWithContentsOfURL:[NSURL fileURLWithPath:string]];
                [imageView setImage:image];
                break;
            }
            case EXTENSION_WIDGET_SPIN_ICON:
            {
                assert([control isKindOfClass:[NSProgressIndicator class]]);
                NSProgressIndicator *progressIndicator = (NSProgressIndicator *)control;
                if (widget->i_spin_loops != 0)
                    [progressIndicator startAnimation:self];
                else
                    [progressIndicator stopAnimation:self];
                break;
            }
        }
    }
}

/**
 * Ask the dialogs provider to create a new dialog
 **/
static int extensionDialogCallback(vlc_object_t *p_this, const char *psz_variable,
                                   vlc_value_t old_val, vlc_value_t new_val,
                                   void *param)
{
    @autoreleasepool {
        (void) p_this;
        (void) psz_variable;
        (void) old_val;
        (void) param;

        ExtensionsDialogProvider *extensionDialogProvider = [ExtensionsDialogProvider sharedInstance];
        if (!extensionDialogProvider)
            return VLC_EGENERIC;
        if (!new_val.p_address)
            return VLC_EGENERIC;

        extension_dialog_t *p_dialog = (extension_dialog_t*) new_val.p_address;
        [extensionDialogProvider manageDialog:p_dialog];
        return VLC_SUCCESS;
    }
}

@interface ExtensionsDialogProvider ()
@end

@implementation ExtensionsDialogProvider

+ (ExtensionsDialogProvider *)sharedInstance
{
    static ExtensionsDialogProvider *sharedInstance = nil;
    static dispatch_once_t pred;
    dispatch_once(&pred, ^{
        sharedInstance = [[ExtensionsDialogProvider alloc] init];
    });

    return sharedInstance;
}

- (id)init
{
    self = [super init];
    if (self) {
        intf_thread_t *p_intf = VLCIntf;
        var_Create(p_intf, "dialog-extension", VLC_VAR_ADDRESS);
        var_AddCallback(p_intf, "dialog-extension", extensionDialogCallback, (__bridge void *)self);
        dialog_Register(p_intf);
    }
    return self;
}

- (void)dealloc
{
    intf_thread_t *p_intf = VLCIntf;
    var_DelCallback(p_intf, "dialog-extension", extensionDialogCallback, (__bridge void *)self);
}

- (void)performEventWithObject:(NSValue *)objectValue ofType:(const char*)type
{
    NSString *typeString = [NSString stringWithUTF8String:type];

    if ([typeString isEqualToString: @"dialog-extension"]) {
        [self performSelectorOnMainThread:@selector(updateExtensionDialog:)
                               withObject:objectValue
                            waitUntilDone:YES];

    }
    else
        msg_Err(VLCIntf, "unhandled dialog type: '%s'", type);
}

- (void)triggerClick:(id)sender
{
    assert([sender isKindOfClass:[VLCDialogButton class]]);
    VLCDialogButton *button = sender;
    extension_widget_t *widget = [button widget];

    vlc_mutex_lock(&widget->p_dialog->lock);
    if (widget->type == EXTENSION_WIDGET_BUTTON)
        extension_WidgetClicked(widget->p_dialog, widget);
    else
        widget->b_checked = [button state] == NSOnState;
    vlc_mutex_unlock(&widget->p_dialog->lock);
}

- (void)syncTextField:(NSNotification *)notifcation
{
    id sender = [notifcation object];
    assert([sender isKindOfClass:[VLCDialogTextField class]]);
    VLCDialogTextField *field = sender;
    extension_widget_t *widget = [field widget];

    vlc_mutex_lock(&widget->p_dialog->lock);
    free(widget->psz_text);
    widget->psz_text = strdup([[field stringValue] UTF8String]);
    vlc_mutex_unlock(&widget->p_dialog->lock);
}

- (void)tableViewSelectionDidChange:(NSNotification *)notifcation
{
    id sender = [notifcation object];
    assert(sender && [sender isKindOfClass:[VLCDialogList class]]);
    VLCDialogList *list = sender;

    struct extension_widget_value_t *value;
    unsigned i = 0;
    NSIndexSet *selectedIndexes = [list selectedRowIndexes];
    for (value = [list widget]->p_values; value != NULL; value = value->p_next, i++)
        value->b_selected = (YES == [selectedIndexes containsIndex:i]);
}

- (void)popUpSelectionChanged:(id)sender
{
    assert([sender isKindOfClass:[VLCDialogPopUpButton class]]);
    VLCDialogPopUpButton *popup = sender;
    struct extension_widget_value_t *value;
    unsigned i = 0;
    for (value = [popup widget]->p_values; value != NULL; value = value->p_next, i++)
        value->b_selected = (i == [popup indexOfSelectedItem]);

}

- (NSSize)windowWillResize:(NSWindow *)sender toSize:(NSSize)frameSize
{
    NSView *contentView = [sender contentView];
    assert([contentView isKindOfClass:[VLCDialogGridView class]]);
    VLCDialogGridView *gridView = (VLCDialogGridView *)contentView;

    NSRect rect = NSMakeRect(0, 0, 0, 0);
    rect.size = frameSize;
    rect = [sender contentRectForFrameRect:rect];
    rect.size = [gridView flexSize:rect.size];
    rect = [sender frameRectForContentRect:rect];
    return rect.size;
}

- (BOOL)windowShouldClose:(id)sender
{
    assert([sender isKindOfClass:[VLCDialogWindow class]]);
    VLCDialogWindow *window = sender;
    extension_dialog_t *dialog = [window dialog];
    extension_DialogClosed(dialog);
    dialog->p_sys_intf = NULL;
    return YES;
}

- (void)updateWidgets:(extension_dialog_t *)dialog
{
    extension_widget_t *widget;
    VLCDialogWindow *dialogWindow = (__bridge VLCDialogWindow *)(dialog->p_sys_intf);

    FOREACH_ARRAY(widget, dialog->widgets) {
        if (!widget)
            continue; /* Some widgets may be NULL@this point */

        BOOL shouldDestroy = widget->b_kill;
        NSView *control = CFBridgingRelease(widget->p_sys_intf);
        BOOL update = widget->b_update;

        if (!control && !shouldDestroy) {
            control = createControlFromWidget(widget, self);
            updateControlFromWidget(control, widget, self);
            widget->p_sys_intf = (void *)CFBridgingRetain(control);
            update = YES; // Force update and repositionning
            [control setHidden:widget->b_hide];
        }

        if (update && !shouldDestroy) {
            updateControlFromWidget(control, widget, self);
            [control setHidden:widget->b_hide];

            int row = widget->i_row - 1;
            int col = widget->i_column - 1;
            int hsp = __MAX(1, widget->i_horiz_span);
            int vsp = __MAX(1, widget->i_vert_span);
            if (row < 0) {
                row = 4;
                col = 0;
            }

            VLCDialogGridView *gridView = (VLCDialogGridView *)[dialogWindow contentView];
            [gridView addSubview:control atRow:row column:col rowSpan:vsp colSpan:hsp];

            widget->b_update = false;
        }

        if (shouldDestroy) {
            VLCDialogGridView *gridView = (VLCDialogGridView *)[dialogWindow contentView];
            [gridView removeSubview:control];
            widget->p_sys_intf = NULL;
        }
    }
    FOREACH_END()
}

/** Create a dialog
 * Note: Lock on p_dialog->lock must be held. */
- (VLCDialogWindow *)createExtensionDialog:(extension_dialog_t *)p_dialog
{
    VLCDialogWindow *dialogWindow;

    BOOL shouldDestroy = p_dialog->b_kill;
    if (!shouldDestroy) {
        NSRect content = NSMakeRect(0, 0, 1, 1);
        dialogWindow = [[VLCDialogWindow alloc] initWithContentRect:content
                                                          styleMask:NSTitledWindowMask | NSClosableWindowMask | NSResizableWindowMask
                                                            backing:NSBackingStoreBuffered
                                                              defer:NO];
        [dialogWindow setDelegate:self];
        [dialogWindow setDialog:p_dialog];
        [dialogWindow setTitle:toNSStr(p_dialog->psz_title)];

        VLCDialogGridView *gridView = [[VLCDialogGridView alloc] init];
        [gridView setAutoresizingMask:NSViewHeightSizable | NSViewWidthSizable];
        [dialogWindow setContentView:gridView];

        p_dialog->p_sys_intf = (void *)CFBridgingRetain(dialogWindow);
    }

    [self updateWidgets:p_dialog];

    if (shouldDestroy) {
        [dialogWindow setDelegate:nil];
        [dialogWindow close];
        p_dialog->p_sys_intf = NULL;
        dialogWindow = nil;
    }

    return dialogWindow;
}

/** Destroy a dialog
 * Note: Lock on p_dialog->lock must be held. */
- (int)destroyExtensionDialog:(extension_dialog_t *)p_dialog
{
    assert(p_dialog);

    VLCDialogWindow *dialogWindow = CFBridgingRelease(p_dialog->p_sys_intf);
    if (!dialogWindow) {
        msg_Warn(VLCIntf, "dialog window not found");
        return VLC_EGENERIC;
    }

    [dialogWindow setDelegate:nil];
    dialogWindow = nil;

    p_dialog->p_sys_intf = NULL;
    vlc_cond_signal(&p_dialog->cond);
    return VLC_SUCCESS;
}

/**
 * Update/Create/Destroy a dialog
 **/
- (VLCDialogWindow *)updateExtensionDialog:(NSValue *)o_value
{
    extension_dialog_t *p_dialog = [o_value pointerValue];

    VLCDialogWindow *dialogWindow = (__bridge VLCDialogWindow*) p_dialog->p_sys_intf;
    if (p_dialog->b_kill && !dialogWindow) {
        /* This extension could not be activated properly but tried
           to create a dialog. We must ignore it. */
        return NULL;
    }

    vlc_mutex_lock(&p_dialog->lock);
    if (!p_dialog->b_kill && !dialogWindow) {
        dialogWindow = [self createExtensionDialog:p_dialog];

        BOOL visible = !p_dialog->b_hide;
        if (visible) {
            [dialogWindow center];
            [dialogWindow makeKeyAndOrderFront:self];
        } else
            [dialogWindow orderOut:nil];

        [dialogWindow setHas_lock:NO];
    }
    else if (!p_dialog->b_kill && dialogWindow) {
        [dialogWindow setHas_lock:YES];
        [self updateWidgets:p_dialog];
        if (strcmp([[dialogWindow title] UTF8String],
                    p_dialog->psz_title) != 0) {
            NSString *titleString = toNSStr(p_dialog->psz_title);

            [dialogWindow setTitle:titleString];
        }

        [dialogWindow setHas_lock:NO];

        BOOL visible = !p_dialog->b_hide;
        if (visible)
            [dialogWindow makeKeyAndOrderFront:self];
        else
            [dialogWindow orderOut:nil];
    }
    else if (p_dialog->b_kill) {
        [self destroyExtensionDialog:p_dialog];
    }
    vlc_cond_signal(&p_dialog->cond);
    vlc_mutex_unlock(&p_dialog->lock);
    return dialogWindow;
}

/**
 * Ask the dialog manager to create/update/kill the dialog. Thread-safe.
 **/
- (void)manageDialog:(extension_dialog_t *)p_dialog
{
    assert(p_dialog);
    ExtensionsManager *extMgr = [ExtensionsManager sharedInstance];
    assert(extMgr != NULL);

    NSValue *o_value = [NSValue valueWithPointer:p_dialog];
    [self performSelectorOnMainThread:@selector(updateExtensionDialog:)
                           withObject:o_value
                        waitUntilDone:YES];
}

@end
